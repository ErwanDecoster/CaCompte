import Foundation

/// Résultat après application des règles (doublement Skyjo, bonus Yams…).
public struct ScoreEntry: Sendable, Codable, Equatable {
    public let participantID: Participant.ID
    public let rawValue: Int
    public let computedValue: Int
    public let explanation: String?
    public let detail: ScoreDetail?
    public let modifiers: Set<ModifierID>

    public init(
        participantID: Participant.ID,
        rawValue: Int,
        computedValue: Int,
        explanation: String? = nil,
        detail: ScoreDetail? = nil,
        modifiers: Set<ModifierID> = []
    ) {
        self.participantID = participantID
        self.rawValue = rawValue
        self.computedValue = computedValue
        self.explanation = explanation
        self.detail = detail
        self.modifiers = modifiers
    }
}

public struct Round: Sendable, Codable, Equatable {
    public let index: Int
    public let entries: [ScoreEntry]
    public let committedAt: Date
    public let note: String?

    public init(index: Int, entries: [ScoreEntry], committedAt: Date, note: String? = nil) {
        self.index = index
        self.entries = entries
        self.committedAt = committedAt
        self.note = note
    }
}
