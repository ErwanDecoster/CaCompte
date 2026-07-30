import Foundation

public enum MatchEvent: Sendable, Codable, Equatable {
    case matchCreated(gameID: String, rulesVersion: Int, variants: VariantSelection, participants: [Participant])
    case roundCommitted(RoundDraft)
    case roundAmended(index: Int, draft: RoundDraft)
    case roundRemoved(index: Int)
    case matchAbandoned(at: Date)
    /// Doc 05 « Jeu libre » et tout jeu à `manualStop` (Scrabble, Qwirkle…) : `endCheck` ne
    /// peut pas détecter cette fin tout seul, elle n'est déclenchée que par une action
    /// explicite du joueur — contrairement à `matchAbandoned`, elle produit un statut `.ended`
    /// normal (classement final écrit, comptée dans les statistiques de profil).
    case matchEndedManually
    case noteAdded(roundIndex: Int, text: String)
}

/// Un événement horodaté logiquement (horloge de Lamport) — l'unité du journal rejouable.
public struct StampedEvent: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let lamport: UInt64
    public let deviceID: String
    /// Affichage uniquement, jamais pour trier : seul `(lamport, deviceID)` fait foi.
    public let occurredAt: Date
    public let event: MatchEvent

    public init(id: UUID = UUID(), lamport: UInt64, deviceID: String, occurredAt: Date, event: MatchEvent) {
        self.id = id
        self.lamport = lamport
        self.deviceID = deviceID
        self.occurredAt = occurredAt
        self.event = event
    }
}
