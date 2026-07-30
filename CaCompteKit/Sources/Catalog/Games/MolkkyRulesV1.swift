import Domain

/// Doc 05 « Mölkky » — la seule règle de score « non monotone » du catalogue : dépasser 50
/// ramène le total à 25 plutôt que de continuer à grimper. `computedValue` porte, pour la
/// manche qui fait déborder, le delta nécessaire pour atterrir exactement sur 25 plutôt que la
/// valeur brute lancée — le cumul générique (`MatchState.totals()`, simple somme des
/// `computedValue`) retombe alors juste sans logique spéciale côté lecture.
///
/// `endCheck`/`standings` sont entièrement propres à Mölkky : la fin est immédiate (pas de
/// « dernier tour », `completeRound: false`) dès qu'un total vaut exactement 50, ou dès qu'il ne
/// reste plus qu'un joueur non éliminé (trois lancers à 0 d'affilée). `targetExact` n'est pas
/// géré par le classement par défaut de `GameRules` (conçu pour `lowestWins`/`highestWins`),
/// d'où le classement par distance à 50.
public struct MolkkyRulesV1: GameRules {
    public static let engineID = "molkky.v1"

    public init() {}

    public func score(_ draft: RoundDraft, in state: MatchState, definition: GameDefinition) -> [ScoreEntry] {
        draft.inputs.map { input in
            let priorTotal = state.total(for: input.participantID)
            let candidate = priorTotal + input.rawValue
            let bust = candidate > 50
            return ScoreEntry(
                participantID: input.participantID,
                rawValue: input.rawValue,
                computedValue: bust ? (25 - priorTotal) : input.rawValue,
                explanation: bust ? "Dépassement de 50 : retour à 25." : nil,
                detail: input.detail,
                modifiers: input.modifiers
            )
        }
    }

    public func endCheck(_ state: MatchState, definition: GameDefinition) -> EndCheck {
        let totals = state.totals()
        if state.participants.contains(where: { (totals[$0.id] ?? 0) == 50 }) {
            return .ended(reason: .targetReached)
        }
        if state.participants.count > 1 {
            let survivors = state.participants.filter { !isEliminated($0.id, in: state) }
            if survivors.count == 1 {
                return .ended(reason: .elimination)
            }
        }
        return .continue
    }

    public func standings(_ state: MatchState, definition: GameDefinition) -> [Standing] {
        let totals = state.totals()
        let groupedByDistance = Dictionary(grouping: state.participants.map(\.id)) { abs(50 - (totals[$0] ?? 0)) }
        let orderedDistances = groupedByDistance.keys.sorted()

        var result: [Standing] = []
        var rank = 1
        for distance in orderedDistances {
            let group = groupedByDistance[distance] ?? []
            for id in group {
                result.append(Standing(participantID: id, rank: rank, score: totals[id] ?? 0, sharedWith: group.filter { $0 != id }))
            }
            rank += group.count
        }
        return result
    }

    /// Trois lancers d'affilée à 0 éliminent — dérivé de l'historique à chaque appel, jamais
    /// stocké (doc 04, event sourcing).
    private func isEliminated(_ id: Participant.ID, in state: MatchState) -> Bool {
        let values = state.rounds
            .compactMap { round in round.entries.first { $0.participantID == id } }
            .map(\.rawValue)
        guard values.count >= 3 else { return false }
        return values.suffix(3).allSatisfy { $0 == 0 }
    }
}
