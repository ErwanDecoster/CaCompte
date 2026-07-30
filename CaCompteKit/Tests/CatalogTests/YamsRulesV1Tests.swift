import Domain
import Foundation
import Testing
@testable import Catalog

/// Complète le golden `yams-01-bonus-et-grille-complete` (qui ne teste pas d'égalité) : doc 05
/// « Départage : total de section basse, puis ex æquo ». Un cas isolé, minimal, plutôt qu'un
/// second golden de 26 manches pour la seule égalité — `higherSecondaryScore` n'est pas résolu
/// par le classement générique (doc 04), c'est `YamsRulesV1.standings` qui le fait.
@Suite("YamsRulesV1 — départage")
struct YamsRulesV1Tests {
    private func makeDefinition() -> GameDefinition {
        GameDefinition(
            id: "yams-test",
            specVersion: 1,
            rulesVersion: 1,
            name: .init(fr: "Test"),
            symbol: "circle",
            players: .init(min: 2, max: 8),
            scoring: .init(
                direction: .highestWins,
                entry: .init(
                    kind: .categorySheet,
                    categories: [
                        .init(id: "catUp", label: .init(fr: "Haut"), section: .upper, scoring: .init(kind: .multipleOf, value: 5)),
                        .init(id: "catA", label: .init(fr: "A"), section: .lower, scoring: .init(kind: .fixed, value: 10)),
                        .init(id: "catB", label: .init(fr: "B"), section: .lower, scoring: .init(kind: .fixed, value: 20)),
                    ]
                )
            ),
            engine: YamsRulesV1.engineID,
            end: .init(conditions: [.init(type: .allSheetsComplete, scope: .allPlayers, completeRound: false)]),
            tieBreak: [.higherSecondaryScore, .shared]
        )
    }

    private func detail(_ categoryID: String) -> ScoreDetail {
        ScoreDetail(payload: try! JSONEncoder().encode(YamsCategoryDetail(categoryID: categoryID)))
    }

    @Test("Égalité au total général départagée par la section basse")
    func tieBrokenBySecondaryScore() throws {
        let definition = makeDefinition()
        let rules = YamsRulesV1()
        let alice = Participant(displayName: "Alice", seatIndex: 0)
        let bob = Participant(displayName: "Bob", seatIndex: 1)

        var state = MatchState(matchID: UUID(), gameID: "yams-test", rulesVersion: 1, variants: VariantSelection(), participants: [alice, bob])
        let engine = MatchEngine(now: { Date(timeIntervalSince1970: 0) })

        // Alice : catUp=5 (1 dé), catA obtenu (10), catB raté (0) -> total 15, section basse 10.
        state = engine.reduce(state, .roundCommitted(RoundDraft(index: 0, inputs: [ScoreInput(participantID: alice.id, rawValue: 1, detail: detail("catUp"))])), rules: rules, definition: definition)
        state = engine.reduce(state, .roundCommitted(RoundDraft(index: 1, inputs: [ScoreInput(participantID: alice.id, rawValue: 1, detail: detail("catA"))])), rules: rules, definition: definition)
        state = engine.reduce(state, .roundCommitted(RoundDraft(index: 2, inputs: [ScoreInput(participantID: alice.id, rawValue: 0, detail: detail("catB"))])), rules: rules, definition: definition)

        // Bob : catUp=15 (3 dés), catA raté (0), catB raté (0) -> total 15, section basse 0.
        state = engine.reduce(state, .roundCommitted(RoundDraft(index: 3, inputs: [ScoreInput(participantID: bob.id, rawValue: 3, detail: detail("catUp"))])), rules: rules, definition: definition)
        state = engine.reduce(state, .roundCommitted(RoundDraft(index: 4, inputs: [ScoreInput(participantID: bob.id, rawValue: 0, detail: detail("catA"))])), rules: rules, definition: definition)
        state = engine.reduce(state, .roundCommitted(RoundDraft(index: 5, inputs: [ScoreInput(participantID: bob.id, rawValue: 0, detail: detail("catB"))])), rules: rules, definition: definition)

        #expect(state.status == .ended)
        #expect(state.total(for: alice.id) == 15)
        #expect(state.total(for: bob.id) == 15)

        let standings = rules.standings(state, definition: definition)
        let aliceStanding = try #require(standings.first { $0.participantID == alice.id })
        let bobStanding = try #require(standings.first { $0.participantID == bob.id })

        #expect(aliceStanding.rank == 1, "Alice a la meilleure section basse (10 > 0) malgré l'égalité au total.")
        #expect(bobStanding.rank == 2)
        #expect(aliceStanding.sharedWith.isEmpty)
    }
}
