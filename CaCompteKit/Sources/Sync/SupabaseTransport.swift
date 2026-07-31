import Foundation
import Supabase

/// Doc utilisateur P9 — remplace `WifiTransport`/`BLETransport` (voir historique Git : cinq
/// correctifs BLE distincts, tous réels et vérifiés, sans que la connexion ne s'établisse jamais
/// entre deux appareils physiques). La fiabilité de connexion/reconnexion est déléguée à un SDK
/// websocket mature (Supabase Realtime) plutôt qu'à du code réseau/Bluetooth maison.
///
/// **Un canal Realtime par partie** (`match:<matchID>`), où l'hôte et chaque pair rejoignent le
/// même canal :
/// - **Presence** identifie qui est là — l'hôte s'annonce toujours sous la clé constante `"host"`
///   (pas besoin qu'un pair la connaisse à l'avance), chaque pair sous son propre `deviceID`.
///   Une déconnexion (y compris abrupte : app tuée, réseau perdu) déclenche un événement de
///   présence côté serveur — remplace toute la détection de déconnexion BLE/Wi-Fi qui a posé tant
///   de problèmes cette session.
/// - **Broadcast** transporte chaque message avec un en-tête `from`/`to` (identifiants ci-dessus)
///   en plus du contenu déjà chiffré (`WireCodec`, inchangé) — `SupabaseTransportSession` filtre
///   simplement ce flux partagé par ces champs pour se comporter comme une session point-à-point
///   ordinaire du point de vue de `LiveSession`, qui ne voit aucune différence.
/// - Pas de fragmentation nécessaire (contrairement au BLE, contraint par la taille d'écriture
///   d'une caractéristique) : un message tient dans un seul frame JSON.
///
/// **Découverte** : `open_games` (Postgres, migration `supabase/migrations`) résout un code
/// d'appairage tapé à la main vers le `matchID` correspondant — remplace le scan Wi-Fi/BLE, qui
/// n'a jamais eu besoin d'exister avec Supabase (le code suffit, pas de proximité physique).
public final class SupabaseTransport: @unchecked Sendable {
    private let client: SupabaseClient
    private let deviceID: String
    private let deviceName: String
    private let platform: WireMessage.Platform

    // MARK: Hôte
    private var hostChannel: RealtimeChannelV2?
    private var hostMatchID: UUID?
    private var sessionsByPeerID: [String: SupabaseTransportSession] = [:]
    private let acceptedStream: AsyncStream<any TransportSession>
    private let acceptedContinuation: AsyncStream<any TransportSession>.Continuation
    private var hostTasks: [Task<Void, Never>] = []
    private var hostStatusSubscription: RealtimeSubscription?

    // MARK: Pair
    private var joinedChannel: RealtimeChannelV2?
    private var joinedTasks: [Task<Void, Never>] = []
    private var joinedStatusSubscription: RealtimeSubscription?

    /// Doc utilisateur — clé constante côté hôte, jamais le `deviceID` réel : un pair n'a besoin de
    /// connaître que ce sentinel, pas un identifiant d'appareil qu'il n'a aucun moyen d'obtenir à
    /// l'avance (contrairement au `deviceID` d'un pair, qui figure dans son propre `hello`).
    private static let hostPresenceKey = "host"

    public init(deviceID: String, deviceName: String, platform: WireMessage.Platform = .apple) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.platform = platform
        client = SupabaseClient(supabaseURL: SupabaseSyncConfig.projectURL, supabaseKey: SupabaseSyncConfig.anonKey)
        (acceptedStream, acceptedContinuation) = AsyncStream.makeStream()
    }

    // MARK: - Hôte

    public func advertise(matchID: UUID, gameID: String, participantCount: Int, pairingCode: String) async throws {
        hostMatchID = matchID
        try await client.from("open_games").upsert(
            OpenGameRow(pairingCode: pairingCode, matchID: matchID, gameID: gameID, participantCount: participantCount, deviceName: deviceName, platform: platform.rawValue),
            onConflict: "pairing_code"
        ).execute()

        let channel = client.channel("match:\(matchID.uuidString)") { config in
            config.presence.key = Self.hostPresenceKey
        }
        hostChannel = channel

        // Doc : callbacks enregistrés avant `subscribeWithError()`, comme l'exige le SDK.
        let presenceTask = Task { [weak self] in
            for await action in channel.presenceChange() {
                await self?.handleHostPresence(action, channel: channel)
            }
        }
        let broadcastTask = Task { [weak self] in
            for await payload in channel.broadcastStream(event: "msg") {
                await self?.handleHostBroadcast(payload)
            }
        }
        hostTasks = [presenceTask, broadcastTask]

        // Doc utilisateur P9 — remontée : après une mise en arrière-plan assez longue pour que
        // l'OS suspende le processus, le socket se ferme ; au retour au premier plan, le SDK le
        // rouvre et réabonne le canal tout seul (`RealtimeLifecycleManager`), mais ne retrace
        // jamais la présence pour nous — `track()` est un envoi ponctuel, jamais rejoué
        // automatiquement lors d'un ré-abonnement. Sans ce ré-enregistrement à chaque passage à
        // `.subscribed` (le premier compris), l'hôte disparaîtrait silencieusement de la présence
        // pour les pairs déjà connectés après une reconnexion sous-jacente, même si rien d'autre
        // n'a changé de son côté.
        let deviceName = deviceName
        hostStatusSubscription = channel.onStatusChange { status in
            guard status == .subscribed else { return }
            Task { try? await channel.track(["deviceName": deviceName]) }
        }

        try await channel.subscribeWithError()
        try await channel.track(["deviceName": deviceName])
    }

    public func stopAdvertising() async {
        hostStatusSubscription?.cancel()
        hostStatusSubscription = nil
        for task in hostTasks { task.cancel() }
        hostTasks = []
        for session in sessionsByPeerID.values { session.markClosed() }
        sessionsByPeerID = [:]
        if let channel = hostChannel {
            await channel.untrack()
            await channel.unsubscribe()
        }
        hostChannel = nil
        if let matchID = hostMatchID {
            _ = try? await client.from("open_games").delete().eq("match_id", value: matchID.uuidString).execute()
        }
        hostMatchID = nil
    }

    public func acceptIncoming() -> AsyncStream<any TransportSession> {
        acceptedStream
    }

    @MainActor
    private func handleHostPresence(_ action: any PresenceAction, channel: RealtimeChannelV2) {
        for peerID in action.joins.keys where peerID != Self.hostPresenceKey {
            _ = session(forPeer: peerID, channel: channel)
        }
        for peerID in action.leaves.keys {
            sessionsByPeerID[peerID]?.markClosed()
            sessionsByPeerID[peerID] = nil
        }
    }

    @MainActor
    private func handleHostBroadcast(_ payload: JSONObject) {
        guard let envelope = Self.decodeEnvelope(payload), envelope.to == deviceID || envelope.to == Self.hostPresenceKey else { return }
        guard let channel = hostChannel else { return }
        session(forPeer: envelope.from, channel: channel).receive(base64: envelope.data)
    }

    /// Doc utilisateur — remontée : le « hello » d'un pair (broadcast) et son entrée de présence
    /// (« il vient de rejoindre ») arrivent sur le même socket, dans le bon ordre, mais sont
    /// consommés par deux tâches Swift indépendantes (une par `AsyncStream`, présence et
    /// broadcast) : rien ne garantit que la présence soit traitée avant le broadcast. Quand le
    /// broadcast gagnait la course, `sessionsByPeerID` ne contenait pas encore ce pair — son
    /// « hello » était silencieusement perdu, et il n'obtenait jamais de `welcome` (« L'hôte n'a
    /// pas répondu » côté pair, après le délai de `LiveSession.attachToHost`). Créer la session à
    /// la première occurrence, quel que soit le chemin qui arrive en premier, rend le
    /// raccordement robuste à cette course au lieu de dépendre d'un ordre non garanti.
    @MainActor
    private func session(forPeer peerID: String, channel: RealtimeChannelV2) -> SupabaseTransportSession {
        if let existing = sessionsByPeerID[peerID] { return existing }
        let session = SupabaseTransportSession(channel: channel, selfID: deviceID, peerID: peerID, ownsChannel: false)
        sessionsByPeerID[peerID] = session
        acceptedContinuation.yield(session)
        return session
    }

    // MARK: - Pair

    /// Doc utilisateur — remplace le scan Wi-Fi/BLE : une simple lecture par code, sans aucune
    /// notion de proximité physique. Traduit l'erreur PostgREST « aucune ligne » (`.single()` sur
    /// un code qui ne correspond à rien) en une erreur du domaine `Sync`, plutôt que de laisser
    /// fuiter un type PostgREST jusqu'à l'app — qui ne dépend pas directement de `supabase-swift`.
    public func resolveGame(code: String) async throws -> DiscoveredHost {
        let row: OpenGameRow
        do {
            row = try await client.from("open_games")
                .select()
                .eq("pairing_code", value: code)
                .single()
                .execute()
                .value
        } catch let error as PostgrestError where error.code == "PGRST116" {
            throw SupabaseTransportError.gameNotFound
        }
        return DiscoveredHost(
            id: row.matchID,
            deviceName: row.deviceName,
            gameID: row.gameID,
            participantCount: row.participantCount,
            platform: WireMessage.Platform(rawValue: row.platform) ?? .apple
        )
    }

    public func connect(to host: DiscoveredHost) async throws -> any TransportSession {
        let channel = client.channel("match:\(host.id.uuidString)") { [deviceID] config in
            config.presence.key = deviceID
        }
        let session = SupabaseTransportSession(channel: channel, selfID: deviceID, peerID: Self.hostPresenceKey, ownsChannel: true)
        joinedChannel = channel

        let broadcastTask = Task { [weak self, weak session] in
            for await payload in channel.broadcastStream(event: "msg") {
                guard let self, let session else { return }
                if let envelope = Self.decodeEnvelope(payload), envelope.to == self.deviceID {
                    session.receive(base64: envelope.data)
                }
            }
        }
        // Doc utilisateur — remplace `LiveSession.hostLeft` détecté côté BLE/Wi-Fi : l'hôte quitte
        // la présence du canal (déconnexion propre ou abrupte, le serveur Realtime la détecte dans
        // les deux cas) → cette session se ferme, exactement comme une coupure réseau avant.
        let presenceTask = Task { [weak session] in
            for await action in channel.presenceChange() {
                if action.leaves[Self.hostPresenceKey] != nil {
                    session?.markClosed()
                }
            }
        }
        joinedTasks = [broadcastTask, presenceTask]

        // Doc utilisateur P9 — même remontée que côté hôte (voir `advertise`) : un pair dont le
        // socket a été rouvert par le SDK après une mise en arrière-plan doit retracer sa présence
        // lui-même, `track()` n'étant jamais rejoué automatiquement par un ré-abonnement.
        let deviceName = deviceName
        joinedStatusSubscription = channel.onStatusChange { status in
            guard status == .subscribed else { return }
            Task { try? await channel.track(["deviceName": deviceName]) }
        }

        try await channel.subscribeWithError()
        try await channel.track(["deviceName": deviceName])
        return session
    }

    private static func decodeEnvelope(_ payload: JSONObject) -> SupabaseEnvelope? {
        guard let inner = payload["payload"] else { return nil }
        return try? inner.decode(as: SupabaseEnvelope.self)
    }
}

private struct SupabaseEnvelope: Codable {
    let from: String
    let to: String
    let data: String
}

public enum SupabaseTransportError: Error, Sendable, Equatable {
    /// Aucune ligne `open_games` pour ce code — code erroné, périmé (partie déjà arrêtée), ou
    /// jamais existé.
    case gameNotFound
}

struct OpenGameRow: Codable {
    let pairingCode: String
    let matchID: UUID
    let gameID: String
    let participantCount: Int
    let deviceName: String
    let platform: String

    enum CodingKeys: String, CodingKey {
        case pairingCode = "pairing_code"
        case matchID = "match_id"
        case gameID = "game_id"
        case participantCount = "participant_count"
        case deviceName = "device_name"
        case platform
    }
}

/// Doc utilisateur P9 — clé **anon/publique** Supabase : conçue pour être embarquée dans un client
/// (protégée par les politiques RLS de `open_games`, pas par le secret), à la différence d'une clé
/// `service_role`. Le contenu réel des manches reste protégé par `SessionCrypto` (chiffrement dérivé
/// du code d'appairage), pas par cette clé.
enum SupabaseSyncConfig {
    static let projectURL = URL(string: "https://utmviqounxbsrubhrgex.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV0bXZpcW91bnhic3J1YmhyZ2V4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU0ODg2NDIsImV4cCI6MjEwMTA2NDY0Mn0.3gS9ziRDe-Llem9NQI6b1BdpUnbmK0r8XTlWThE4ZCo"
}

final class SupabaseTransportSession: TransportSession, @unchecked Sendable {
    private let channel: RealtimeChannelV2
    private let selfID: String
    private let peerID: String
    private let ownsChannel: Bool
    private let stream: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation

    init(channel: RealtimeChannelV2, selfID: String, peerID: String, ownsChannel: Bool) {
        self.channel = channel
        self.selfID = selfID
        self.peerID = peerID
        self.ownsChannel = ownsChannel
        (stream, continuation) = AsyncStream.makeStream()
    }

    var incoming: AsyncStream<Data> { stream }

    func send(_ data: Data) async throws {
        let envelope = SupabaseEnvelope(from: selfID, to: peerID, data: data.base64EncodedString())
        try await channel.broadcast(event: "msg", message: envelope)
    }

    func receive(base64: String) {
        guard let data = Data(base64Encoded: base64) else { return }
        continuation.yield(data)
    }

    func markClosed() {
        continuation.finish()
    }

    /// Doc utilisateur — une session côté hôte (une par pair) ne possède pas le canal, partagé
    /// entre tous les pairs de cette partie : la fermer ne doit jamais le désabonner (ça
    /// couperait tout le monde). Seule la session du pair (`ownsChannel: true`, un canal par
    /// pair qui rejoint) le fait vraiment.
    func close() async {
        continuation.finish()
        guard ownsChannel else { return }
        await channel.untrack()
        await channel.unsubscribe()
    }
}
