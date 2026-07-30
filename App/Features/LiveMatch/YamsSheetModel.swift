import Catalog
import Domain
import Foundation
import Store
import SwiftData

/// Doc 05 « Yams » — contrairement à `LiveMatchModel`, une « manche » ici est le tour d'un
/// seul joueur sur une seule catégorie (`RoundDraft.inputs` ne contient qu'une entrée) : pas
/// d'`activeSeatIndex` ni de pavé numérique partagé, la grille se remplit dans n'importe quel
/// ordre.
@MainActor
@Observable
final class YamsSheetModel {
    private(set) var state: MatchState {
        didSet { MatchLiveActivityController.refresh(definition: definition, rules: rules, state: state) }
    }

    private(set) var validationErrorMessage: String?

    let definition: GameDefinition
    private let rules: any GameRules
    private let match: MatchRecord
    private let repository: MatchRepository
    private let catalog: GameCatalog

    init(match: MatchRecord, context: ModelContext, catalog: GameCatalog) throws {
        self.match = match
        self.repository = MatchRepository(context: context)
        self.catalog = catalog
        self.definition = try catalog.definition(for: match.gameID, version: match.rulesVersion)
        self.rules = try catalog.rules(for: match.gameID, version: match.rulesVersion)
        self.state = try repository.loadState(match, catalog: catalog)
        MatchLiveActivityController.refresh(definition: definition, rules: rules, state: state)
    }

    var participants: [Participant] {
        state.participants.sorted { $0.seatIndex < $1.seatIndex }
    }

    var participantRecords: [ParticipantRecord] {
        match.participants.sorted { $0.seatIndex < $1.seatIndex }
    }

    var categories: [GameDefinition.Category] {
        definition.scoring.entry.categories ?? []
    }

    var finalStandings: [Standing] {
        rules.standings(state, definition: definition)
    }

    var isConcluded: Bool {
        state.status == .ended || state.status == .abandoned
    }

    func abandon() {
        state = (try? repository.abandonMatch(match, catalog: catalog)) ?? state
    }

    /// Catégories déjà remplies pour ce joueur, indexées par `categoryID`.
    func filledCategories(for participantID: Participant.ID) -> [String: ScoreEntry] {
        var result: [String: ScoreEntry] = [:]
        for round in state.rounds {
            for entry in round.entries where entry.participantID == participantID {
                if let id = categoryID(from: entry.detail) {
                    result[id] = entry
                }
            }
        }
        return result
    }

    func submit(rawValue: Int, participantID: Participant.ID, categoryID: String) {
        let detail = ScoreDetail(payload: try! JSONEncoder().encode(YamsCategoryDetail(categoryID: categoryID)))
        let draft = RoundDraft(
            index: state.rounds.count,
            inputs: [ScoreInput(participantID: participantID, rawValue: rawValue, detail: detail)]
        )

        if case .invalid(let errors) = rules.validate(draft, in: state, definition: definition) {
            validationErrorMessage = errors.first?.message
            return
        }

        do {
            state = try repository.commitRound(draft, to: match, catalog: catalog)
            validationErrorMessage = nil
        } catch {
            validationErrorMessage = "La saisie n'a pas pu être enregistrée."
        }
    }

    func dismissError() {
        validationErrorMessage = nil
    }

    private func categoryID(from detail: ScoreDetail?) -> String? {
        guard let payload = detail?.payload,
              let decoded = try? JSONDecoder().decode(YamsCategoryDetail.self, from: payload) else { return nil }
        return decoded.categoryID
    }
}
