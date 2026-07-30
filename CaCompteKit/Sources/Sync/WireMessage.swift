import Domain
import Foundation

/// Doc 09 — protocole applicatif unique, identique quel que soit le transport actif (Wi-Fi ou
/// BLE, voir `Transport`). `welcome` porte le journal complet plutôt qu'un type d'instantané
/// séparé : le pair qui rejoint appelle `MatchEngine.replay(log:)`, la même fonction qu'au
/// lancement de l'app — une seule façon de reconstruire un `MatchState`.
public struct WireMessage: Codable, Sendable, Equatable {
    public let protocolVersion: Int
    public let matchID: UUID
    public let kind: Kind

    public init(protocolVersion: Int = 1, matchID: UUID, kind: Kind) {
        self.protocolVersion = protocolVersion
        self.matchID = matchID
        self.kind = kind
    }

    public enum Platform: String, Codable, Sendable, Equatable {
        case apple
        case android
    }

    public enum Kind: Codable, Sendable, Equatable {
        /// `deviceID` (le même que celui qui horodate ses `StampedEvent`) permet à l'hôte de
        /// relier « cette manche vient de X » à « X, c'est Théo » — sans lui, seul un UUID
        /// technique accompagne chaque manche distante, impossible à attribuer à un pair affiché.
        case hello(deviceName: String, appVersion: String, platform: Platform, role: Role, deviceID: String)
        case welcome(log: [StampedEvent], role: Role)
        case events([StampedEvent])
        case proposal([StampedEvent])
        case rejection(eventID: UUID, reason: String)
        case heartbeat(lamport: UInt64)
        case goodbye
    }
}
