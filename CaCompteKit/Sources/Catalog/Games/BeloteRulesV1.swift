import Domain

/// Doc 05 « Belote » — premier jeu par équipes. Simplification assumée pour cette V1(validée
/// avec l'auteur du projet) : « Belote classique », sans annonce de contrat chiffrée — le
/// preneur réussit s'il dépasse 81 points (majorité de 162), sinon la défense encaisse 162 à
/// plat. La coinche/contrée (annonces chiffrées, multiplicateurs ×2/×4) reste, comme documenté,
/// une variante de la v1.2.
///
/// Astuce d'implémentation : chaque coéquipier reçoit une entrée **identique** (même
/// `computedValue`, le score de l'équipe) plutôt qu'une entrée par équipe. `endCheck` et
/// `standings` de l'extension par défaut de `GameRules` opèrent déjà sur `state.totals()` par
/// participant — dupliquer l'entrée suffit à leur faire produire le bon comportement pour une
/// équipe sans surcharger ni l'un ni l'autre (seuls `validate`/`score` sont propres à Belote,
/// exactement comme `SkyjoRulesV1`).
public struct BeloteRulesV1: GameRules {
    public static let engineID = "belote.v1"

    public init() {}

    public func validate(_ draft: RoundDraft, in state: MatchState, definition: GameDefinition) -> ValidationResult {
        guard draft.inputs.count == 2 else {
            return .invalid([ValidationError(field: .general, message: "Deux équipes attendues par donne.")])
        }
        let takers = draft.inputs.filter { $0.modifiers.contains("isTaker") }
        guard takers.count == 1, let takerInput = takers.first else {
            return .invalid([ValidationError(field: .general, message: "Une seule équipe preneuse par donne.")])
        }
        guard (0...162).contains(takerInput.rawValue) else {
            return .invalid([ValidationError(field: .participant(takerInput.participantID), message: "Points invalides (0 à 162).")])
        }
        return .valid
    }

    public func score(_ draft: RoundDraft, in state: MatchState, definition: GameDefinition) -> [ScoreEntry] {
        guard draft.inputs.count == 2,
              let takerInput = draft.inputs.first(where: { $0.modifiers.contains("isTaker") }),
              let defenderInput = draft.inputs.first(where: { $0.participantID != takerInput.participantID }) else {
            return []
        }

        let capotInput = draft.inputs.first { $0.modifiers.contains("capot") }
        var takerScore: Int
        var defenderScore: Int

        if let capotInput {
            let takerAchievedCapot = capotInput.participantID == takerInput.participantID
            takerScore = takerAchievedCapot ? 250 : 0
            defenderScore = takerAchievedCapot ? 0 : 250
        } else if takerInput.rawValue > 81 {
            takerScore = takerInput.rawValue
            defenderScore = 162 - takerInput.rawValue
        } else {
            // Le preneur chute : la défense encaisse 162 à plat (pas de bonus de contrat,
            // aucun montant n'étant annoncé dans cette version simplifiée).
            takerScore = 0
            defenderScore = 162
        }

        if takerInput.modifiers.contains("beloteRebelote") { takerScore += 20 }
        if defenderInput.modifiers.contains("beloteRebelote") { defenderScore += 20 }

        return teamEntries(takerInput, computedValue: takerScore, state: state)
            + teamEntries(defenderInput, computedValue: defenderScore, state: state)
    }

    private func teamEntries(_ input: ScoreInput, computedValue: Int, state: MatchState) -> [ScoreEntry] {
        guard let representative = state.participants.first(where: { $0.id == input.participantID }) else { return [] }
        return state.participants
            .filter { $0.teamID == representative.teamID }
            .map { participant in
                ScoreEntry(
                    participantID: participant.id,
                    rawValue: input.rawValue,
                    computedValue: computedValue,
                    modifiers: input.modifiers
                )
            }
    }
}
