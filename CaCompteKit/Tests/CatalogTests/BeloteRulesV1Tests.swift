import Domain
import Foundation
import Testing
@testable import Catalog

/// Complète le golden `belote-01-equipes-et-seuil` (qui ne couvre pas le capot) : doc 05
/// « Capot (250) ». Cas isolé plutôt qu'un golden supplémentaire pour cette seule branche.
@Suite("BeloteRulesV1 — capot")
struct BeloteRulesV1Tests {
    private func makeDefinition() -> GameDefinition {
        GameDefinition(
            id: "belote-test",
            specVersion: 1,
            rulesVersion: 1,
            name: .init(fr: "Test"),
            symbol: "circle",
            players: .init(min: 4, max: 4, teams: .init(size: 2)),
            scoring: .init(direction: .highestWins, entry: .init(kind: .structured)),
            engine: BeloteRulesV1.engineID,
            end: .init(conditions: [.init(type: .scoreThreshold, value: 1000)]),
            tieBreak: [.shared]
        )
    }

    @Test("Le capot rapporte 250 à l'équipe qui le réalise, 0 à l'autre — même si ce n'est pas l'équipe preneuse")
    func capotAwardsFlatTwoHundredFifty() throws {
        let definition = makeDefinition()
        let rules = BeloteRulesV1()
        let alice = Participant(displayName: "Alice", seatIndex: 0, teamID: "A")
        let bob = Participant(displayName: "Bob", seatIndex: 1, teamID: "A")
        let chloe = Participant(displayName: "Chloé", seatIndex: 2, teamID: "B")
        let david = Participant(displayName: "David", seatIndex: 3, teamID: "B")

        var state = MatchState(
            matchID: UUID(), gameID: "belote-test", rulesVersion: 1,
            variants: VariantSelection(), participants: [alice, bob, chloe, david]
        )
        let engine = MatchEngine(now: { Date(timeIntervalSince1970: 0) })

        // B prend mais c'est la défense (A) qui réalise le capot : A doit tout de même
        // encaisser 250, B (preneur) 0 — le capot n'est pas réservé au preneur.
        let draft = RoundDraft(index: 0, inputs: [
            ScoreInput(participantID: chloe.id, rawValue: 40, modifiers: ["isTaker"]),
            ScoreInput(participantID: alice.id, rawValue: 122, modifiers: ["capot"]),
        ])
        state = engine.reduce(state, .roundCommitted(draft), rules: rules, definition: definition)

        #expect(state.total(for: alice.id) == 250)
        #expect(state.total(for: bob.id) == 250, "Le coéquipier reçoit le même score que sa partenaire.")
        #expect(state.total(for: chloe.id) == 0)
        #expect(state.total(for: david.id) == 0)
    }
}
