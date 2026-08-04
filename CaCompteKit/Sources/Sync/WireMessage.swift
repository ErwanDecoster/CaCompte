import Domain
import Foundation

/// Doc 09 — protocole applicatif, indépendant du transport actif (`SupabaseTransport`, voir
/// `TransportSession`). `welcome` porte le journal complet plutôt qu'un type d'instantané
/// séparé : le pair qui rejoint appelle `MatchEngine.replay(log:)`, la même fonction qu'au
/// lancement de l'app — une seule façon de reconstruire un `MatchState`.
public struct WireMessage: Codable, Sendable, Equatable {
    public let protocolVersion: Int
    /// Identifiant de la **session de partage**, stable tant qu'elle dure — pas de la partie
    /// courante (`matchID`), qui peut changer plusieurs fois sans jamais rouvrir la connexion ni
    /// changer de clé (doc 09 « Fin de partie »).
    public let sessionID: UUID
    public let kind: Kind

    public init(protocolVersion: Int = 1, sessionID: UUID, kind: Kind) {
        self.protocolVersion = protocolVersion
        self.sessionID = sessionID
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
        /// L'hôte enchaîne une nouvelle partie (même jeu rejoué ou jeu différent) sans rompre la
        /// session : diffusé à tous les pairs déjà connectés, contrairement à `welcome` qui ne
        /// sert qu'au pair qui vient de rejoindre. Porte le journal complet de la nouvelle partie
        /// — un pair qui le reçoit doit repartir d'un journal vide plutôt que d'y ajouter les
        /// événements (ils appartiennent à une autre partie).
        case matchChanged(log: [StampedEvent])
        case proposal([StampedEvent])
        case rejection(eventID: UUID, reason: String)
        case heartbeat(lamport: UInt64)
        case goodbye
    }
}
