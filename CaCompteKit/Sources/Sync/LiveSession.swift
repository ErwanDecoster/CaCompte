import CryptoKit
import Domain
import Foundation

/// Doc 09 « Modèle : hôte autoritaire ». Un seul type, deux rôles possibles :
///
/// - **Hôte** : garde son propre `MatchState` pour arbitrer (`GameRules.validate` puis
///   `MatchEngine.reduce`) les propositions des contributeurs, et rediffuse ce qui est accepté.
/// - **Pair (contributeur/observateur)** : relais fin vers l'hôte, sans copie locale de
///   `MatchState` — c'est `LiveMatchModel` (couche app) qui rejoue `events` avec son propre
///   `MatchEngine`, exactement comme au lancement de l'app (doc 02).
///
/// `LiveSession` ignore lequel de `WifiTransport` ou `BLETransport` (ADR-0014) est actif : elle
/// ne parle qu'au protocole `Transport`.
public actor LiveSession {
    public enum SessionError: Error, Sendable, Equatable {
        case notConnected
        case notAuthorized
        case noActiveMatch
        /// L'hôte n'a jamais répondu au `hello` dans le délai imparti — code d'appairage erroné
        /// (l'hôte ne peut alors pas déchiffrer le message, et ne répond jamais) ou hôte
        /// injoignable. Avant ce délai explicite, cette situation ne produisait aucune erreur :
        /// l'écran restait sur « Connexion à la partie… » indéfiniment.
        case noResponseFromHost
    }

    public struct RemoteValidationFailure: Error, Sendable, Equatable {
        public let reason: String
    }

    private let deviceID: String
    private let catalog: GameCatalog
    private let engine: MatchEngine

    private var clock = LamportClock()
    private var role: Role = .observer
    private var matchID: UUID?
    private var pairingKey: SymmetricKey?

    // Hôte uniquement : état de vérité pour arbitrer les propositions.
    /// Doc utilisateur P9 — restreint qui peut rejoindre en contributeur ; un pair qui demande ce
    /// rôle alors que c'est désactivé est silencieusement ramené à observateur (doc `hello`
    /// ci-dessous). `true` par défaut : ne change rien pour qui ne touche pas à ce réglage.
    private var allowsContributors = true
    private var hostState: MatchState?
    private var hostRules: (any GameRules)?
    private var hostDefinition: GameDefinition?
    private var hostLog: [StampedEvent] = []
    private var peerConnections: [UUID: PeerConnection] = [:]

    // Pair non-hôte uniquement : connexion vers l'hôte.
    private var hostConnection: (any TransportSession)?

    private struct PeerConnection {
        let session: any TransportSession
        var deviceName: String
        var role: Role
        var deviceID: String?
    }

    private let eventContinuation: AsyncStream<StampedEvent>.Continuation
    public nonisolated let events: AsyncStream<StampedEvent>

    private let rejectionContinuation: AsyncStream<(eventID: UUID, reason: String)>.Continuation
    public nonisolated let rejections: AsyncStream<(eventID: UUID, reason: String)>

    /// Doc 09 — un instantané des pairs connectés, republié à chaque connexion/déconnexion/
    /// confirmation de rôle, pour que l'écran d'invitation affiche « Théo est connecté ».
    public struct ConnectedPeer: Sendable, Identifiable, Equatable {
        public let id: UUID
        public let deviceName: String
        public let role: Role
        /// Le même identifiant que celui qui horodate les `StampedEvent` de ce pair
        /// (`StampedEvent.deviceID`) — permet à l'appelant de relier « cette manche vient de X »
        /// à « X, c'est Théo ». `nil` tant que le `hello` n'est pas encore arrivé.
        public let deviceID: String?
    }

    private let peerUpdateContinuation: AsyncStream<[ConnectedPeer]>.Continuation
    public nonisolated let peerUpdates: AsyncStream<[ConnectedPeer]>

    /// Doc 09 — un pair non-hôte s'y abonne pour savoir que l'hôte a arrêté le partage ou que la
    /// connexion a été perdue (départ explicite ou coupure réseau, traités de façon identique :
    /// dans les deux cas la partie continue localement, seul le lien réseau a disparu).
    private let hostLeftContinuation: AsyncStream<Void>.Continuation
    public nonisolated let hostLeft: AsyncStream<Void>

    private var welcomeContinuation: CheckedContinuation<Void, Error>?

    /// Doc 09 « Appairage et chiffrement » — affiché en clair par l'hôte à qui rejoint. Exposé
    /// ici plutôt que sur `SessionCrypto` (interne au module) : c'est la seule partie du
    /// mécanisme de chiffrement que la couche App a besoin d'appeler directement.
    public static func generatePairingCode() -> String {
        SessionCrypto.generatePairingCode()
    }

    /// Doc 09 — le rôle réellement assigné par l'hôte, connu seulement après le `welcome` que
    /// `attachToHost` attend déjà : l'hôte peut renvoyer un rôle différent de celui demandé
    /// (restriction « observateur uniquement », doc utilisateur P9).
    public func currentRole() -> Role {
        role
    }

    public init(deviceID: String, catalog: GameCatalog, engine: MatchEngine = MatchEngine()) {
        self.deviceID = deviceID
        self.catalog = catalog
        self.engine = engine
        (events, eventContinuation) = AsyncStream.makeStream()
        (rejections, rejectionContinuation) = AsyncStream.makeStream()
        (peerUpdates, peerUpdateContinuation) = AsyncStream.makeStream()
        (hostLeft, hostLeftContinuation) = AsyncStream.makeStream()
    }

    // MARK: - Hôte

    /// `initialLog` est rejoué immédiatement : l'hôte doit connaître l'état courant pour arbitrer
    /// dès la première proposition, pas seulement à la première manche saisie après le partage.
    public func startHosting(log initialLog: [StampedEvent], pairingCode: String, allowsContributors: Bool = true) throws {
        let replayed = try engine.replay(initialLog, catalog: catalog)
        hostState = replayed
        hostDefinition = try catalog.definition(for: replayed.gameID, version: replayed.rulesVersion)
        hostRules = try catalog.rules(for: replayed.gameID, version: replayed.rulesVersion)
        hostLog = initialLog
        role = .host
        matchID = replayed.matchID
        clock = LamportClock(startingAt: initialLog.map(\.lamport).max() ?? 0)
        pairingKey = SessionCrypto.deriveKey(pairingCode: pairingCode, matchID: replayed.matchID)
        self.allowsContributors = allowsContributors
    }

    /// Le journal faisant foi vient de `MatchRepository` (hôte), pas de `LiveSession` — cette
    /// méthode resynchronise l'état interne d'arbitrage après chaque écriture locale de l'hôte
    /// (saisie, annulation, fin de partie) et diffuse aux pairs connectés les seuls événements
    /// apparus depuis le dernier appel. Le journal n'est jamais raccourci (doc 04 « Event
    /// sourcing » — une annulation ajoute un `roundRemoved`, elle ne retire rien) : la longueur
    /// suffit à identifier ce qui est nouveau.
    public func syncHostLog(_ log: [StampedEvent]) async throws {
        let newEvents = log.count > hostLog.count ? Array(log.suffix(from: hostLog.count)) : []
        let replayed = try engine.replay(log, catalog: catalog)
        hostState = replayed
        hostDefinition = try catalog.definition(for: replayed.gameID, version: replayed.rulesVersion)
        hostRules = try catalog.rules(for: replayed.gameID, version: replayed.rulesVersion)
        hostLog = log
        matchID = replayed.matchID
        if let latest = log.map(\.lamport).max() {
            clock = LamportClock(startingAt: latest)
        }
        if !newEvents.isEmpty {
            await broadcastToConnectedPeers(.events(newEvents))
        }
    }

    /// Doc utilisateur P9 — modifiable en cours de partage : s'applique aux prochaines connexions
    /// (`hello`), ne rétrograde pas un contributeur déjà connecté quand on la désactive.
    public func setAllowsContributors(_ allowed: Bool) {
        allowsContributors = allowed
    }

    /// Arrête le partage côté hôte : prévient chaque pair connecté (`.goodbye`, déjà géré par
    /// `handleFromPeer` en face) puis ferme réellement chaque connexion. Sans ce dernier point,
    /// rien ne clôt jamais le socket sous-jacent : un pair qui a quitté resterait indéfiniment
    /// listé comme connecté (bug observé en recette).
    public func stopHosting() async {
        for connection in peerConnections.values {
            if let pairingKey, let matchID {
                try? await send(WireMessage(matchID: matchID, kind: .goodbye), to: connection.session, key: pairingKey)
            }
            await connection.session.close()
        }
        peerConnections = [:]
        publishPeerUpdate()
    }

    /// Une connexion entrante par pair qui rejoint — venue de `Transport.acceptIncoming()`.
    public func acceptConnection(_ session: any TransportSession) {
        let peerID = UUID()
        peerConnections[peerID] = PeerConnection(session: session, deviceName: "…", role: .observer, deviceID: nil)
        Task { [weak self] in await self?.listenToPeer(session, peerID: peerID) }
    }

    private func listenToPeer(_ session: any TransportSession, peerID: UUID) async {
        for await data in session.incoming {
            await handleFromPeer(data, peerID: peerID)
        }
        peerConnections[peerID] = nil
        publishPeerUpdate()
    }

    private func handleFromPeer(_ data: Data, peerID: UUID) async {
        guard let pairingKey, let message = try? WireCodec.decode(data, key: pairingKey) else { return }
        guard let connection = peerConnections[peerID] else { return }

        switch message.kind {
        case .hello(let deviceName, _, _, let requestedRole, let deviceID):
            let assignedRole = (requestedRole == .contributor && !allowsContributors) ? .observer : requestedRole
            peerConnections[peerID]?.deviceName = deviceName
            peerConnections[peerID]?.role = assignedRole
            peerConnections[peerID]?.deviceID = deviceID
            publishPeerUpdate()
            await sendWelcome(to: connection.session, role: assignedRole)
        case .proposal(let proposedEvents):
            for proposed in proposedEvents {
                await arbitrate(proposed, from: peerID, session: connection.session)
            }
        case .heartbeat:
            break
        case .goodbye:
            peerConnections[peerID] = nil
            publishPeerUpdate()
        case .welcome, .events, .rejection:
            break // jamais envoyés par un pair vers l'hôte
        }
    }

    private func publishPeerUpdate() {
        let snapshot = peerConnections.map { ConnectedPeer(id: $0.key, deviceName: $0.value.deviceName, role: $0.value.role, deviceID: $0.value.deviceID) }
        peerUpdateContinuation.yield(snapshot)
    }

    private func sendWelcome(to session: any TransportSession, role: Role) async {
        guard let pairingKey, let matchID else { return }
        try? await send(WireMessage(matchID: matchID, kind: .welcome(log: hostLog, role: role)), to: session, key: pairingKey)
    }

    private func arbitrate(_ proposed: StampedEvent, from peerID: UUID, session: any TransportSession) async {
        guard peerConnections[peerID]?.role == .contributor else {
            await reject(proposed.id, reason: "Rôle non autorisé à proposer une manche.", to: session)
            return
        }
        do {
            // L'id de la proposition est préservé (seul l'horloge change) : le contributeur peut
            // ainsi reconnaître la confirmation de son événement optimiste plutôt que d'y voir un
            // second événement indépendant.
            let stamped = try hostCommit(proposed.event, id: proposed.id)
            await broadcastToConnectedPeers(.events([stamped]))
        } catch let failure as RemoteValidationFailure {
            await reject(proposed.id, reason: failure.reason, to: session)
        } catch {
            await reject(proposed.id, reason: "Aucune partie active.", to: session)
        }
    }

    /// Valide, réduit, journalise et publie localement — partagé entre les propositions saisies
    /// par l'hôte lui-même (`propose`) et celles acceptées d'un contributeur (`arbitrate`). Dans
    /// les deux cas l'événement final porte l'horloge de l'hôte, jamais celle proposée par le
    /// pair (doc 09).
    private func hostCommit(_ event: MatchEvent, id: UUID = UUID()) throws -> StampedEvent {
        guard let hostRules, let hostDefinition, let currentState = hostState else {
            throw SessionError.noActiveMatch
        }
        if case .roundCommitted(let draft) = event,
           case .invalid(let errors) = hostRules.validate(draft, in: currentState, definition: hostDefinition) {
            throw RemoteValidationFailure(reason: errors.first?.message ?? "Manche invalide.")
        }
        let stamped = stamp(event, id: id)
        hostState = engine.reduce(currentState, stamped.event, rules: hostRules, definition: hostDefinition)
        hostLog.append(stamped)
        eventContinuation.yield(stamped)
        return stamped
    }

    private func reject(_ eventID: UUID, reason: String, to session: any TransportSession) async {
        guard let pairingKey, let matchID else { return }
        try? await send(WireMessage(matchID: matchID, kind: .rejection(eventID: eventID, reason: reason)), to: session, key: pairingKey)
    }

    private func broadcastToConnectedPeers(_ kind: WireMessage.Kind) async {
        guard let pairingKey, let matchID else { return }
        let message = WireMessage(matchID: matchID, kind: kind)
        for connection in peerConnections.values {
            try? await send(message, to: connection.session, key: pairingKey)
        }
    }

    // MARK: - Pair (contributeur / observateur)

    /// Doc 09 — se connecte et **attend la confirmation de l'hôte** (`welcome`) avant de
    /// retourner. Sans ce délai explicite, un code d'appairage erroné ne produisait aucune
    /// erreur : le message `hello` chiffré avec la mauvaise clé arrivait bien à l'hôte, qui ne
    /// pouvait simplement pas le déchiffrer et ne répondait donc jamais — l'appelant restait sur
    /// « Connexion à la partie… » indéfiniment, sans savoir que quelque chose avait échoué.
    public func attachToHost(
        _ session: any TransportSession,
        matchID: UUID,
        pairingCode: String,
        requestedRole: Role,
        deviceName: String,
        appVersion: String,
        timeout: Duration = .seconds(8)
    ) async throws {
        role = requestedRole
        self.matchID = matchID
        hostConnection = session
        let key = SessionCrypto.deriveKey(pairingCode: pairingCode, matchID: matchID)
        pairingKey = key

        // `welcomeContinuation` est posé avant tout `await` : le `hello` est envoyé et l'écoute
        // démarrée depuis une tâche séparée, pour ne jamais risquer qu'un `welcome` arrive et
        // soit traité avant que ce continuation existe (course possible si `send` suspend et
        // qu'une tâche concurrente tourne déjà sur l'acteur).
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            welcomeContinuation = continuation

            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.send(
                        WireMessage(matchID: matchID, kind: .hello(deviceName: deviceName, appVersion: appVersion, platform: .apple, role: requestedRole, deviceID: self.deviceID)),
                        to: session,
                        key: key
                    )
                } catch {
                    await self.failPendingWelcome(with: error)
                    return
                }
                await self.listenToHost(session)
            }

            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                await self?.failPendingWelcome(with: SessionError.noResponseFromHost)
            }
        }
    }

    private func failPendingWelcome(with error: Error) async {
        guard let continuation = welcomeContinuation else { return }
        welcomeContinuation = nil
        await hostConnection?.close()
        hostConnection = nil
        continuation.resume(throwing: error)
    }

    /// Départ volontaire d'un pair non-hôte — prévient l'hôte (`.goodbye`) puis ferme la
    /// connexion. Sans cet appel explicite, rien ne fermait jamais le socket : l'hôte continuait
    /// de lister ce pair comme connecté bien après qu'il ait quitté l'écran (bug observé en
    /// recette).
    public func leave() async {
        guard role != .host, let hostConnection else { return }
        if let pairingKey, let matchID {
            try? await send(WireMessage(matchID: matchID, kind: .goodbye), to: hostConnection, key: pairingKey)
        }
        await hostConnection.close()
        self.hostConnection = nil
    }

    private func listenToHost(_ session: any TransportSession) async {
        for await data in session.incoming {
            await handleFromHost(data)
        }
        hostConnection = nil
        hostLeftContinuation.yield(())
    }

    private func handleFromHost(_ data: Data) async {
        guard let pairingKey, let message = try? WireCodec.decode(data, key: pairingKey) else { return }

        switch message.kind {
        case .welcome(let log, let assignedRole):
            role = assignedRole
            if let latest = log.map(\.lamport).max() {
                clock = LamportClock(startingAt: latest)
            }
            for stamped in log {
                eventContinuation.yield(stamped)
            }
            if let continuation = welcomeContinuation {
                welcomeContinuation = nil
                continuation.resume()
            }
        case .events(let newEvents):
            for stamped in newEvents {
                clock.observe(stamped.lamport)
                eventContinuation.yield(stamped)
            }
        case .rejection(let eventID, let reason):
            rejectionContinuation.yield((eventID: eventID, reason: reason))
        case .goodbye:
            hostLeftContinuation.yield(())
        case .heartbeat, .hello, .proposal:
            break // jamais envoyés par l'hôte vers un pair
        }
    }

    // MARK: - Commun

    /// Point d'entrée unique pour `LiveMatchModel`, quel que soit le rôle local (doc 02) : elle
    /// n'a pas à savoir si cet appareil est l'hôte ou un contributeur.
    public func propose(_ event: MatchEvent) async throws {
        switch role {
        case .host:
            let stamped = try hostCommit(event)
            await broadcastToConnectedPeers(.events([stamped]))
        case .contributor:
            guard let hostConnection, let pairingKey, let matchID else { throw SessionError.notConnected }
            let optimistic = stamp(event)
            eventContinuation.yield(optimistic) // application optimiste locale (doc 09)
            try await send(WireMessage(matchID: matchID, kind: .proposal([optimistic])), to: hostConnection, key: pairingKey)
        case .observer:
            throw SessionError.notAuthorized
        }
    }

    private func stamp(_ event: MatchEvent, id: UUID = UUID()) -> StampedEvent {
        StampedEvent(id: id, lamport: clock.tick(), deviceID: deviceID, occurredAt: Date(), event: event)
    }

    private func send(_ message: WireMessage, to session: any TransportSession, key: SymmetricKey) async throws {
        try await session.send(try WireCodec.encode(message, key: key))
    }
}
