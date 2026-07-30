/// Doc 04 — quatre méthodes, aucune n'a d'effet de bord, aucune ne prend de dépendance. Les
/// valeurs par défaut de l'extension couvrent entièrement `generic.sum.v1` : un jeu simple
/// n'implémente rien du tout. Un jeu avec un calcul propre (Skyjo) ne surcharge que ce qui
/// l'exige — `endCheck`/`standings` restent déclaratifs tant que `end`/`tieBreak` du JSON
/// suffisent à les décrire.
public protocol GameRules: Sendable {
    /// Identifiant du moteur, tel qu'écrit dans le JSON : `"skyjo.v1"`.
    static var engineID: String { get }

    func validate(_ draft: RoundDraft, in state: MatchState, definition: GameDefinition) -> ValidationResult

    func score(_ draft: RoundDraft, in state: MatchState, definition: GameDefinition) -> [ScoreEntry]

    func endCheck(_ state: MatchState, definition: GameDefinition) -> EndCheck

    func standings(_ state: MatchState, definition: GameDefinition) -> [Standing]
}

public enum EndCheck: Sendable, Equatable {
    case `continue`
    case finalRound(triggeredBy: Participant.ID, reason: EndReason)
    case ended(reason: EndReason)
}

public enum EndReason: String, Sendable, Codable, Equatable {
    case scoreThreshold
    case roundLimit
    case targetReached
    case allSheetsComplete
    case elimination
    case manualStop
}

/// Doc 03 : classement final. `sharedWith` liste les autres participants au même rang — vide
/// si le rang n'est pas partagé.
public struct Standing: Sendable, Codable, Equatable {
    public let participantID: Participant.ID
    public let rank: Int
    public let score: Int
    public let sharedWith: [Participant.ID]

    public init(participantID: Participant.ID, rank: Int, score: Int, sharedWith: [Participant.ID] = []) {
        self.participantID = participantID
        self.rank = rank
        self.score = score
        self.sharedWith = sharedWith
    }
}

public extension GameRules {
    func validate(_ draft: RoundDraft, in state: MatchState, definition: GameDefinition) -> ValidationResult {
        let entry = definition.scoring.entry
        var errors: [ValidationError] = []
        var warnings: [String] = []

        for input in draft.inputs {
            if let min = entry.min, input.rawValue < min {
                errors.append(ValidationError(
                    field: .participant(input.participantID),
                    message: "Score sous le minimum autorisé (\(min))."
                ))
            }
            if let max = entry.max, input.rawValue > max {
                errors.append(ValidationError(
                    field: .participant(input.participantID),
                    message: "Score au-dessus du maximum autorisé (\(max))."
                ))
            }
            if let warnBelow = entry.warnBelow, input.rawValue < warnBelow {
                warnings.append("Score inhabituel, à vérifier.")
            }
            if let warnAbove = entry.warnAbove, input.rawValue > warnAbove {
                warnings.append("Score inhabituel, à vérifier.")
            }
        }

        if !errors.isEmpty { return .invalid(errors) }
        if !warnings.isEmpty { return .warning(warnings) }
        return .valid
    }

    func score(_ draft: RoundDraft, in state: MatchState, definition: GameDefinition) -> [ScoreEntry] {
        draft.inputs.map { input in
            ScoreEntry(
                participantID: input.participantID,
                rawValue: input.rawValue,
                computedValue: input.rawValue,
                detail: input.detail,
                modifiers: input.modifiers
            )
        }
    }

    func endCheck(_ state: MatchState, definition: GameDefinition) -> EndCheck {
        let totals = state.totals()
        for condition in definition.end.conditions {
            let threshold = condition.resolvedValue(variants: state.variants)
            switch condition.type {
            case .scoreThreshold:
                let reached = state.participants.contains {
                    condition.comparison.evaluate(totals[$0.id] ?? 0, threshold)
                }
                if reached { return .ended(reason: .scoreThreshold) }
            case .roundLimit:
                if condition.comparison.evaluate(state.rounds.count, threshold) {
                    return .ended(reason: .roundLimit)
                }
            case .targetReached, .allSheetsComplete, .elimination, .manualStop:
                continue // nécessitent des données spécifiques au jeu, pas génériques
            }
        }
        return .continue
    }

    func standings(_ state: MatchState, definition: GameDefinition) -> [Standing] {
        let totals = state.totals()
        let direction = definition.scoring.direction

        let groupedByTotal = Dictionary(grouping: state.participants.map(\.id)) { totals[$0] ?? 0 }
        let orderedTotals = groupedByTotal.keys.sorted { direction == .highestWins ? $0 > $1 : $0 < $1 }

        var result: [Standing] = []
        var rank = 1
        for total in orderedTotals {
            let tied = groupedByTotal[total] ?? []
            let subgroups = resolveTieBreakGroups(tied, rules: definition.tieBreak, state: state, direction: direction)
            for group in subgroups {
                for id in group {
                    result.append(Standing(
                        participantID: id,
                        rank: rank,
                        score: total,
                        sharedWith: group.filter { $0 != id }
                    ))
                }
                rank += group.count
            }
        }
        return result
    }
}

// MARK: - Départage générique (§ charte tieBreak, doc 04)

private func resolveTieBreakGroups(
    _ ids: [Participant.ID],
    rules: [TieBreakRule],
    state: MatchState,
    direction: Direction
) -> [[Participant.ID]] {
    guard ids.count > 1, let rule = rules.first else { return [ids] }

    switch rule {
    case .shared:
        return [ids]
    case .bestSingleRound:
        let values = Dictionary(uniqueKeysWithValues: ids.map { ($0, bestSingleRoundValue($0, state: state, direction: direction)) })
        return groupByKey(ids, values: values, ascending: direction != .highestWins, rules: Array(rules.dropFirst()), state: state, direction: direction)
    case .worstSingleRound:
        let values = Dictionary(uniqueKeysWithValues: ids.map { ($0, bestSingleRoundValue($0, state: state, direction: direction)) })
        return groupByKey(ids, values: values, ascending: direction == .highestWins, rules: Array(rules.dropFirst()), state: state, direction: direction)
    case .fewestRoundsClosed:
        let values = Dictionary(uniqueKeysWithValues: ids.map { ($0, roundsClosedCount($0, state: state)) })
        return groupByKey(ids, values: values, ascending: true, rules: Array(rules.dropFirst()), state: state, direction: direction)
    case .mostRoundsWon, .lowerSecondaryScore, .higherSecondaryScore, .headToHead:
        // Nécessitent des données non modélisées génériquement (classement par manche, score
        // secondaire propre au jeu) — un moteur spécifique les surchargerait s'il en avait besoin.
        return resolveTieBreakGroups(ids, rules: Array(rules.dropFirst()), state: state, direction: direction)
    }
}

private func groupByKey(
    _ ids: [Participant.ID],
    values: [Participant.ID: Int],
    ascending: Bool,
    rules: [TieBreakRule],
    state: MatchState,
    direction: Direction
) -> [[Participant.ID]] {
    let grouped = Dictionary(grouping: ids) { values[$0] ?? 0 }
    let orderedKeys = grouped.keys.sorted { ascending ? $0 < $1 : $0 > $1 }
    return orderedKeys.flatMap { key in
        resolveTieBreakGroups(grouped[key] ?? [], rules: rules, state: state, direction: direction)
    }
}

private func bestSingleRoundValue(_ id: Participant.ID, state: MatchState, direction: Direction) -> Int {
    let values = state.rounds.compactMap { round in
        round.entries.first { $0.participantID == id }?.computedValue
    }
    guard !values.isEmpty else { return 0 }
    return direction == .highestWins ? (values.max() ?? 0) : (values.min() ?? 0)
}

private func roundsClosedCount(_ id: Participant.ID, state: MatchState) -> Int {
    state.rounds.reduce(0) { count, round in
        let closed = round.entries.first { $0.participantID == id }?.modifiers.contains(.closedRound) ?? false
        return count + (closed ? 1 : 0)
    }
}
