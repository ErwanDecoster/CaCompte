import Catalog
import Domain
import Store
import SwiftData

/// Doc 05 « Belote » — une « manche » ici est une donne complète : les deux équipes sont
/// connues en même temps (contrairement à Yams, une entrée par équipe suffit par donne, pas
/// une par joueur).
@MainActor
@Observable
final class BeloteRoundModel {
    private(set) var state: MatchState
    private(set) var validationErrorMessage: String?

    var takerTeamID: String
    var takerPoints: Int = 82
    var isCapot = false
    var beloteRebeloteTeamID: String?

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
        let loadedState = try repository.loadState(match, catalog: catalog)
        self.state = loadedState
        self.takerTeamID = Self.teamIDs(in: loadedState).first ?? "A"
    }

    /// Équipes triées, chacune avec ses membres dans l'ordre des sièges.
    var teams: [(teamID: String, members: [Participant])] {
        Self.teamIDs(in: state).map { teamID in
            (teamID, state.participants.filter { $0.teamID == teamID }.sorted { $0.seatIndex < $1.seatIndex })
        }
    }

    var defenderTeamID: String? {
        teams.map(\.teamID).first { $0 != takerTeamID }
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

    var participantRecords: [ParticipantRecord] {
        match.participants.sorted { $0.seatIndex < $1.seatIndex }
    }

    private static func teamIDs(in state: MatchState) -> [String] {
        Array(Set(state.participants.compactMap(\.teamID))).sorted()
    }

    func submit() {
        guard let defenderTeamID,
              let takerRepresentative = state.participants.first(where: { $0.teamID == takerTeamID }),
              let defenderRepresentative = state.participants.first(where: { $0.teamID == defenderTeamID }) else {
            validationErrorMessage = "Deux équipes complètes sont nécessaires."
            return
        }

        var takerModifiers: Set<ModifierID> = ["isTaker"]
        var defenderModifiers: Set<ModifierID> = []
        if isCapot { takerModifiers.insert("capot") }
        if beloteRebeloteTeamID == takerTeamID { takerModifiers.insert("beloteRebelote") }
        if beloteRebeloteTeamID == defenderTeamID { defenderModifiers.insert("beloteRebelote") }

        let draft = RoundDraft(index: state.rounds.count, inputs: [
            ScoreInput(participantID: takerRepresentative.id, rawValue: takerPoints, modifiers: takerModifiers),
            ScoreInput(participantID: defenderRepresentative.id, rawValue: 162 - takerPoints, modifiers: defenderModifiers),
        ])

        if case .invalid(let errors) = rules.validate(draft, in: state, definition: definition) {
            validationErrorMessage = errors.first?.message
            return
        }

        do {
            state = try repository.commitRound(draft, to: match, catalog: catalog)
            validationErrorMessage = nil
            isCapot = false
            beloteRebeloteTeamID = nil
            takerPoints = 82
        } catch {
            validationErrorMessage = "La donne n'a pas pu être enregistrée."
        }
    }

    func dismissError() {
        validationErrorMessage = nil
    }
}
