import Domain
import Foundation

/// Doc 05 « Yams » — payload de `ScoreDetail`, opaque pour le moteur générique et Skyjo.
/// Identifie la catégorie remplie par cette entrée ; `Domain` reste agnostique du jeu, c'est
/// donc `Catalog` (qui connaît Yams) qui porte ce type, pas `Domain`.
public struct YamsCategoryDetail: Sendable, Codable, Equatable {
    public let categoryID: String

    public init(categoryID: String) {
        self.categoryID = categoryID
    }
}

/// Doc 05 « Yams » — grille individuelle de 13 catégories. Contrairement aux autres jeux du
/// catalogue, une « manche » n'est pas un tour de table homogène : chaque `RoundDraft` ne
/// contient qu'une seule entrée, celle du joueur qui remplit une catégorie. Le bonus de section
/// haute est ajouté à l'entrée qui fait franchir le seuil plutôt que via une entrée synthétique
/// séparée — plus simple à rejouer et à afficher manche par manche.
///
/// Simplification assumée : la règle du « Yams supplémentaire » (+100, joker officiel) n'est
/// pas implémentée — une catégorie ne peut être remplie qu'une fois par joueur, ce qui rend
/// cette règle incompatible avec le modèle actuel sans un remaniement plus large (voir README).
public struct YamsRulesV1: GameRules {
    public static let engineID = "yams.v1"

    public init() {}

    public func validate(_ draft: RoundDraft, in state: MatchState, definition: GameDefinition) -> ValidationResult {
        guard draft.inputs.count == 1, let input = draft.inputs.first else {
            return .invalid([ValidationError(field: .general, message: "Une seule catégorie est remplie par tour.")])
        }
        guard let categoryID = categoryID(of: input), let category = category(withID: categoryID, in: definition) else {
            return .invalid([ValidationError(field: .participant(input.participantID), message: "Catégorie inconnue.")])
        }
        if filledCategories(for: input.participantID, in: state).contains(categoryID) {
            return .invalid([
                ValidationError(field: .participant(input.participantID), message: "Cette catégorie est déjà remplie."),
            ])
        }

        switch category.scoring.kind {
        case .multipleOf:
            guard (0...5).contains(input.rawValue) else {
                return .invalid([ValidationError(field: .participant(input.participantID), message: "Nombre de dés invalide (0 à 5).")])
            }
        case .fixed:
            guard input.rawValue == 0 || input.rawValue == 1 else {
                return .invalid([ValidationError(field: .participant(input.participantID), message: "Valeur invalide.")])
            }
        case .sumOfDice:
            let max = category.scoring.max ?? 30
            guard input.rawValue == 0 || (5...max).contains(input.rawValue) else {
                return .invalid([ValidationError(field: .participant(input.participantID), message: "Somme invalide.")])
            }
        }
        return .valid
    }

    public func score(_ draft: RoundDraft, in state: MatchState, definition: GameDefinition) -> [ScoreEntry] {
        guard let input = draft.inputs.first,
              let categoryID = categoryID(of: input),
              let category = category(withID: categoryID, in: definition) else {
            return []
        }

        let base = baseValue(rawValue: input.rawValue, kind: category.scoring.kind, category: category)

        var bonus = 0
        var explanation: String?
        if category.section == .upper {
            let threshold = state.variants.int("upperBonusThreshold", default: 63)
            let priorUpperTotal = sectionTotal(for: input.participantID, in: state, definition: definition, section: .upper)
            if priorUpperTotal < threshold && priorUpperTotal + base >= threshold {
                bonus = 35
                explanation = "Bonus de section haute (+35)"
            }
        }

        return [
            ScoreEntry(
                participantID: input.participantID,
                rawValue: input.rawValue,
                computedValue: base + bonus,
                explanation: explanation,
                detail: input.detail,
                modifiers: input.modifiers
            ),
        ]
    }

    public func endCheck(_ state: MatchState, definition: GameDefinition) -> EndCheck {
        let categoryCount = definition.scoring.entry.categories?.count ?? 13
        let allComplete = state.participants.allSatisfy { filledCategories(for: $0.id, in: state).count == categoryCount }
        return allComplete ? .ended(reason: .allSheetsComplete) : .continue
    }

    /// Doc 05 : « Départage : total de section basse, puis ex æquo » — `higherSecondaryScore`
    /// n'est pas résolu par le classement générique (données non modélisées), donc surchargé
    /// intégralement ici plutôt que de composer avec `resolveTieBreakGroups`.
    public func standings(_ state: MatchState, definition: GameDefinition) -> [Standing] {
        let totals = state.totals()
        let lowerTotals = Dictionary(uniqueKeysWithValues: state.participants.map {
            ($0.id, sectionTotal(for: $0.id, in: state, definition: definition, section: .lower))
        })

        let groupedByTotal = Dictionary(grouping: state.participants.map(\.id)) { totals[$0] ?? 0 }
        let orderedTotals = groupedByTotal.keys.sorted(by: >) // Yams : le plus haut gagne, toujours.

        var result: [Standing] = []
        var rank = 1
        for total in orderedTotals {
            let tied = groupedByTotal[total] ?? []
            let groupedBySecondary = Dictionary(grouping: tied) { lowerTotals[$0] ?? 0 }
            for secondary in groupedBySecondary.keys.sorted(by: >) {
                let group = groupedBySecondary[secondary] ?? []
                for id in group {
                    result.append(Standing(participantID: id, rank: rank, score: total, sharedWith: group.filter { $0 != id }))
                }
                rank += group.count
            }
        }
        return result
    }

    // MARK: - Aides

    private func categoryID(of input: ScoreInput) -> String? {
        categoryID(from: input.detail)
    }

    private func categoryID(from detail: ScoreDetail?) -> String? {
        guard let payload = detail?.payload,
              let decoded = try? JSONDecoder().decode(YamsCategoryDetail.self, from: payload) else { return nil }
        return decoded.categoryID
    }

    private func category(withID id: String, in definition: GameDefinition) -> GameDefinition.Category? {
        definition.scoring.entry.categories?.first { $0.id == id }
    }

    private func baseValue(rawValue: Int, kind: GameDefinition.Category.Scoring.Kind, category: GameDefinition.Category) -> Int {
        switch kind {
        case .multipleOf: rawValue * (category.scoring.value ?? 0)
        case .fixed: rawValue == 1 ? (category.scoring.value ?? 0) : 0
        case .sumOfDice: rawValue
        }
    }

    private func filledCategories(for participantID: Participant.ID, in state: MatchState) -> Set<String> {
        Set(state.rounds.flatMap { round in
            round.entries.filter { $0.participantID == participantID }.compactMap { categoryID(from: $0.detail) }
        })
    }

    /// Recalculée depuis `rawValue` (jamais `computedValue`) : la section haute peut déjà porter
    /// le bonus sur l'une de ses entrées, ce qui fausserait un cumul basé sur les valeurs
    /// calculées pour déterminer le franchissement du seuil par l'entrée suivante.
    private func sectionTotal(
        for participantID: Participant.ID,
        in state: MatchState,
        definition: GameDefinition,
        section: GameDefinition.Category.Section
    ) -> Int {
        var total = 0
        for round in state.rounds {
            for entry in round.entries where entry.participantID == participantID {
                guard let id = categoryID(from: entry.detail),
                      let category = category(withID: id, in: definition),
                      category.section == section else { continue }
                total += section == .upper
                    ? baseValue(rawValue: entry.rawValue, kind: category.scoring.kind, category: category)
                    : entry.computedValue
            }
        }
        return total
    }
}
