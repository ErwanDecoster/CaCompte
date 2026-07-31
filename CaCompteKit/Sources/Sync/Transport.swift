import Foundation

/// Doc 09 / ADR-0014, révisé P9 — historiquement le seam qui rendait `LiveSession` indifférente à
/// plusieurs transports interchangeables (`WifiTransport`/`BLETransport`). Depuis le passage à
/// Supabase Realtime (seul transport restant, voir `SupabaseTransport`), ce polymorphisme n'a plus
/// d'utilité — mais `LiveSession` ne connaît toujours que `TransportSession` (jamais
/// `SupabaseTransport` directement), donc ce seam reste : juste réduit à ce qui sert encore.
///
/// Une connexion établie. Transporte des octets déjà chiffrés (`WireCodec` s'en charge dans
/// `LiveSession`) — ce protocole ne connaît ni `WireMessage` ni le code d'appairage.
public protocol TransportSession: Sendable {
    var incoming: AsyncStream<Data> { get }
    func send(_ data: Data) async throws
    func close() async
}

/// Doc 09 — contexte d'annonce plafonné : ce qu'un pair voit avant de rejoindre, jamais
/// l'instantané de partie. Résolu via `open_games` (Supabase) à partir d'un code d'appairage,
/// plutôt que découvert par scan réseau/Bluetooth.
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
