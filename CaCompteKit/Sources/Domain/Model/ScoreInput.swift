/// Ce que l'utilisateur a saisi pour un joueur, avant toute règle.
public struct ScoreInput: Sendable, Codable, Equatable {
    public let participantID: Participant.ID
    public let rawValue: Int
    public let detail: ScoreDetail?
    public let modifiers: Set<ModifierID>

    public init(
        participantID: Participant.ID,
        rawValue: Int,
        detail: ScoreDetail? = nil,
        modifiers: Set<ModifierID> = []
    ) {
        self.participantID = participantID
        self.rawValue = rawValue
        self.detail = detail
        self.modifiers = modifiers
    }
}

public struct RoundDraft: Sendable, Codable, Equatable {
    public let index: Int
    public let inputs: [ScoreInput]
    public let note: String?

    public init(index: Int, inputs: [ScoreInput], note: String? = nil) {
        self.index = index
        self.inputs = inputs
        self.note = note
    }
}
