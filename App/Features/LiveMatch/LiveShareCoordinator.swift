import Catalog
import Domain
import Foundation
import Observation
import Store
import Sync
import SwiftData

/// Doc 09 « Fin de partie » (révisé) — pendant de `MatchConnectionCoordinator` côté hôte : porte
/// la session de partage (`LiveSession`/`SupabaseTransport`/code d'appairage) pour toute la durée
/// de l'app, plutôt que pour la durée d'un `LiveMatchModel`/`LiveMatchView`, qui se recrée à
/// chaque nouvelle partie. C'est ce découplage qui permet à une session de survivre à la fin
/// d'une partie et d'enchaîner sur la suivante — même jeu rejoué ou jeu différent — jusqu'à un
/// arrêt explicite (« Arrêter le partage »), qui reste la seule façon de la terminer.
@MainActor
@Observable
final class LiveShareCoordinator {
    static let shared = LiveShareCoordinator()

    private let catalog = GameCatalog.embedded

    private var session: LiveSession?
    private var transport: SupabaseTransport?
    private var match: MatchRecord?
    private var repository: MatchRepository?
    private var sharingTasks: [Task<Void, Never>] = []

    private(set) var pairingCode: String?
    private(set) var connectedPeers: [LiveSession.ConnectedPeer] = []
    /// La partie actuellement diffusée aux pairs connectés — `nil` tant qu'aucune session n'est
    /// active. `LiveMatchModel` compare son propre `match.id` à celui-ci pour savoir s'il est,
    /// lui, la partie affichée par la session en cours (`isSharing`).
    private(set) var attachedMatchID: UUID?
    private(set) var allowsContributors = true
    var isSharing: Bool { session != nil }

    /// Doc utilisateur — un `LiveMatchModel` se recrée à chaque partie ; les flux de `LiveSession`
    /// sont documentés à usage unique (voir `SharedMatchModel`, bug BLE-era d'un second abonné
    /// privé du flux), donc ce coordinateur en reste l'unique consommateur pour toute la durée de
    /// la session et republie ce qu'il faut savoir via ces propriétés `@Observable`, lisibles par
    /// n'importe quel `LiveMatchModel` actif (`.onChange(of:)`) sans jamais re-souscrire
    /// directement à `session.events`.
    private(set) var remoteEventToken = UUID()
    private(set) var remoteEventMatchID: UUID?
    private(set) var remoteEventDeviceID: String?
    private(set) var remoteEventIsRoundCommit = false

    private init() {}

    /// Démarre une toute nouvelle session si aucune n'est active ; sinon équivalent à
    /// `attach(match:context:)` — permet à `ShareSessionView` d'appeler la même méthode dans les
    /// deux cas sans avoir à distinguer « première partie partagée » de « partie suivante ».
    func startSharing(match: MatchRecord, context: ModelContext, deviceName: String, allowsContributors: Bool) async throws {
        guard session == nil else {
            await attach(match: match, context: context)
            return
        }

        let repository = MatchRepository(context: context)
        let newSessionID = UUID()
        let newSession = LiveSession(deviceID: DeviceIdentity.current, catalog: catalog)
        let code = LiveSession.generatePairingCode()
        try await newSession.startHosting(
            log: try repository.currentLog(for: match),
            sessionID: newSessionID,
            pairingCode: code,
            allowsContributors: allowsContributors
        )

        let newTransport = SupabaseTransport(deviceID: DeviceIdentity.current, deviceName: deviceName)
        try await newTransport.advertise(
            sessionID: newSessionID,
            matchID: match.id,
            gameID: match.gameID,
            participantCount: match.participants.count,
            pairingCode: code
        )

        session = newSession
        transport = newTransport
        self.repository = repository
        self.match = match
        pairingCode = code
        self.allowsContributors = allowsContributors
        attachedMatchID = match.id
        connectedPeers = []

        let acceptTask = Task { [weak self] in
            for await incoming in newTransport.acceptIncoming() {
                guard self != nil else { return }
                await newSession.acceptConnection(incoming)
            }
        }
        let eventsTask = Task { [weak self] in
            for await stamped in newSession.events {
                self?.handleRemoteEvent(stamped)
            }
        }
        let peersTask = Task { [weak self] in
            for await peers in newSession.peerUpdates {
                self?.connectedPeers = peers
            }
        }
        sharingTasks = [acceptTask, eventsTask, peersTask]
    }

    /// Doc 09 « Fin de partie » — appelé pour chaque `LiveMatchModel` créé (nouvelle partie ou
    /// reprise d'une partie en cours) : silencieusement sans effet si aucune session n'est active,
    /// et sans effet si déjà attaché à cette partie. Sinon pousse son journal complet à la session
    /// déjà ouverte (`LiveSession.switchMatch`) — sans rouvrir le canal, changer la clé, ni
    /// déconnecter les pairs déjà présents. C'est ce seul appel, fait depuis l'initialiseur de
    /// `LiveMatchModel`, qui fait qu'une nouvelle partie rejoint automatiquement une session déjà
    /// active, sans repasser par « Partager en direct ».
    func attach(match: MatchRecord, context: ModelContext) async {
        guard let session else { return }
        guard attachedMatchID != match.id else { return }

        let repository = MatchRepository(context: context)
        guard let log = try? repository.currentLog(for: match) else { return }
        guard (try? await session.switchMatch(log: log)) != nil else { return }
        try? await transport?.updateActiveMatch(matchID: match.id, gameID: match.gameID, participantCount: match.participants.count)

        self.repository = repository
        self.match = match
        attachedMatchID = match.id
    }

    /// Doc utilisateur — appelé après chaque écriture locale de l'hôte sur la partie actuellement
    /// attachée (saisie, annulation, fin de partie) : ne fait plus qu'une resynchronisation, ne
    /// termine plus jamais la session à elle seule (doc 09 « Fin de partie », révisé — l'ancien
    /// comportement arrêtait automatiquement le partage à la conclusion de la partie).
    func syncLog(for matchID: UUID) async {
        guard let session, let match, let repository, attachedMatchID == matchID else { return }
        guard let log = try? repository.currentLog(for: match) else { return }
        try? await session.syncHostLog(log)
    }

    /// Doc utilisateur P9 — s'applique aux prochaines connexions, pas aux contributeurs déjà
    /// connectés (voir `LiveSession.setAllowsContributors`).
    func setAllowsContributors(_ allowed: Bool) async {
        allowsContributors = allowed
        await session?.setAllowsContributors(allowed)
    }

    /// Seul point d'arrêt d'une session (doc 09 « Fin de partie ») — reprend telle quelle la
    /// logique de fermeture qui vivait auparavant dans `LiveMatchModel.stopSharing`.
    func stopSharing() async {
        await session?.stopHosting()
        for task in sharingTasks { task.cancel() }
        sharingTasks = []
        await transport?.stopAdvertising()
        transport = nil
        session = nil
        repository = nil
        match = nil
        pairingCode = nil
        connectedPeers = []
        attachedMatchID = nil
        allowsContributors = true
    }

    /// Persiste une manche acceptée d'un contributeur distant (`LiveSession.events` ne porte
    /// jamais les écritures locales de l'hôte — voir `LiveSession.hostCommit`, jamais appelé par
    /// `session.propose` côté hôte) et republie ce qu'il faut savoir pour que le `LiveMatchModel`
    /// concerné se resynchronise (`refreshFromRemote`).
    private func handleRemoteEvent(_ stamped: StampedEvent) {
        guard let match, let repository else { return }
        guard (try? repository.appendRemoteEvent(stamped, to: match, catalog: catalog)) != nil else { return }

        remoteEventMatchID = match.id
        remoteEventDeviceID = stamped.deviceID
        if case .roundCommitted = stamped.event {
            remoteEventIsRoundCommit = true
        } else {
            remoteEventIsRoundCommit = false
        }
        remoteEventToken = UUID()
    }
}
