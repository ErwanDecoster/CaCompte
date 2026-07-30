import Domain

/// Doc 04 « Le cas Skyjo, en détail » — le jeu de référence du projet, celui qui justifie la
/// couche impérative. Seuls `validate` (exclusivité du joueur qui ferme) et `score` (le
/// doublement) sont propres à Skyjo ; `endCheck`/`standings` restent ceux de l'extension par
/// défaut de `GameRules`, parce que `end` et `tieBreak` de `skyjo.json` suffisent à les décrire.
public struct SkyjoRulesV1: GameRules {
    public static let engineID = "skyjo.v1"

    public init() {}

    public func validate(_ draft: RoundDraft, in state: MatchState, definition: GameDefinition) -> ValidationResult {
        let closers = draft.inputs.filter { $0.modifiers.contains(.closedRound) }
        guard closers.count == 1 else {
            return .invalid([
                ValidationError(field: .modifier(.closedRound), message: "Un seul joueur ferme la manche."),
            ])
        }

        let extremes = draft.inputs.filter { $0.rawValue < -24 || $0.rawValue > 156 }
        return extremes.isEmpty ? .valid : .warning(["Score inhabituel, à vérifier."])
    }

    public func score(_ draft: RoundDraft, in state: MatchState, definition: GameDefinition) -> [ScoreEntry] {
        let doublingEnabled = state.variants.bool("doublePenalty", default: true)
        let lowest = draft.inputs.map(\.rawValue).min() ?? 0

        return draft.inputs.map { input in
            let closed = input.modifiers.contains(.closedRound)
            let isStrictlyLowest = input.rawValue == lowest
                && draft.inputs.filter { $0.rawValue == lowest }.count == 1
            let penalised = doublingEnabled && closed && !isStrictlyLowest && input.rawValue > 0

            return ScoreEntry(
                participantID: input.participantID,
                rawValue: input.rawValue,
                computedValue: penalised ? input.rawValue * 2 : input.rawValue,
                explanation: penalised
                    ? "Score doublé : a fermé la manche sans le score le plus bas."
                    : nil,
                detail: nil,
                modifiers: input.modifiers
            )
        }
    }
}
