import Foundation

/// Ne se modifie jamais par mutation directe : seul `MatchEngine.reduce` produit un nouvel état,
/// par repli d'un événement (doc 04 « Event sourcing »).
public struct MatchState: Sendable, Codable, Equatable {
    public let matchID: UUID
    public let gameID: String
    public let rulesVersion: Int
    public let variants: VariantSelection
    public let participants: [Participant]
    public private(set) var rounds: [Round]
    public private(set) var status: MatchStatus
    public private(set) var endReason: EndReason?

    public init(
        matchID: UUID,
        gameID: String,
        rulesVersion: Int,
        variants: VariantSelection,
        participants: [Participant]
    ) {
        self.matchID = matchID
        self.gameID = gameID
        self.rulesVersion = rulesVersion
        self.variants = variants
        self.participants = participants
        self.rounds = []
        self.status = .inProgress
        self.endReason = nil
    }

    /// Cumul par joueur, recalculé, jamais stocké.
    public func totals() -> [Participant.ID: Int] {
        var result = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, 0) })
        for round in rounds {
            for entry in round.entries {
                result[entry.participantID, default: 0] += entry.computedValue
            }
        }
        return result
    }

    public func total(for id: Participant.ID) -> Int {
        totals()[id] ?? 0
    }

    // MARK: - Repli d'événement (accès à `apply` réservé à `MatchEngine`, même module)

    mutating func apply(_ event: MatchEvent, rules: any GameRules, definition: GameDefinition, occurredAt: Date) {
        switch event {
        case .matchCreated:
            break // la création construit l'état initial, voir `MatchEngine.replay`.
        case .roundCommitted(let draft):
            commitRound(draft, rules: rules, definition: definition, occurredAt: occurredAt)
        case .roundAmended(_, let draft):
            commitRound(draft, rules: rules, definition: definition, occurredAt: occurredAt)
        case .roundRemoved(let index):
            rounds.removeAll { $0.index == index }
            refreshStatus(rules: rules, definition: definition)
        case .matchAbandoned:
            status = .abandoned
            endReason = nil
        case .matchEndedManually:
            status = .ended
            endReason = .manualStop
        case .noteAdded(let roundIndex, let text):
            if let position = rounds.firstIndex(where: { $0.index == roundIndex }) {
                let existing = rounds[position]
                rounds[position] = Round(index: existing.index, entries: existing.entries, committedAt: existing.committedAt, note: text)
            }
        }
    }

    private mutating func commitRound(_ draft: RoundDraft, rules: any GameRules, definition: GameDefinition, occurredAt: Date) {
        let entries = rules.score(draft, in: self, definition: definition)
        let round = Round(index: draft.index, entries: entries, committedAt: occurredAt, note: draft.note)
        rounds.removeAll { $0.index == draft.index }
        rounds.append(round)
        rounds.sort { $0.index < $1.index }
        refreshStatus(rules: rules, definition: definition)
    }

    private mutating func refreshStatus(rules: any GameRules, definition: GameDefinition) {
        guard status != .abandoned else { return }
        switch rules.endCheck(self, definition: definition) {
        case .continue:
            status = .inProgress
            endReason = nil
        case .finalRound(_, let reason):
            status = .finalRound
            endReason = reason
        case .ended(let reason):
            status = .ended
            endReason = reason
        }
    }
}
