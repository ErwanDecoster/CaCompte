import Foundation

/// Doc 09 / ADR-0014 — le seam qui rend `LiveSession` indifférente au transport actif.
/// `WifiTransport` (mDNS/DNS-SD + socket, `Network.framework`) et `BLETransport` (GATT,
/// `CoreBluetooth`) implémentent ce même protocole ; `LiveSession` ne connaît que celui-ci,
/// exactement comme `MatchEngine` ignore quel `GameRules` elle appelle.
public protocol Transport: Sendable {
    /// Découvre les hôtes qui annoncent une partie, pendant la fenêtre donnée.
    func discover(timeout: Duration) -> AsyncStream<DiscoveredHost>

    /// Annonce cette partie aux appareils à portée. Le contexte d'annonce reste minimal (doc 09) :
    /// identifiant de partie, jeu, nombre de joueurs — jamais le journal d'événements.
    func advertise(matchID: UUID, gameID: String, participantCount: Int) async throws

    func stopAdvertising() async

    /// Connexions entrantes acceptées côté hôte (une par pair qui rejoint).
    func acceptIncoming() -> AsyncStream<any TransportSession>

    /// Connexion sortante côté pair qui rejoint.
    func connect(to host: DiscoveredHost) async throws -> any TransportSession
}

/// Une connexion établie, quel que soit le transport. Transporte des octets déjà chiffrés
/// (`WireCodec` s'en charge dans `LiveSession`) — ce protocole ne connaît ni `WireMessage` ni
/// le code d'appairage.
public protocol TransportSession: Sendable {
    var incoming: AsyncStream<Data> { get }
    func send(_ data: Data) async throws
    func close() async
}

/// Doc 09 — contexte d'annonce plafonné : ce qu'un pair voit avant de rejoindre, jamais
/// l'instantané de partie.
public struct DiscoveredHost: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let deviceName: String
    public let gameID: String
    public let participantCount: Int
    public let platform: WireMessage.Platform

    public init(id: UUID, deviceName: String, gameID: String, participantCount: Int, platform: WireMessage.Platform) {
        self.id = id
        self.deviceName = deviceName
        self.gameID = gameID
        self.participantCount = participantCount
        self.platform = platform
    }
}
