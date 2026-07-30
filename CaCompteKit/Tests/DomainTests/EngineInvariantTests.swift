import Foundation
import Testing
@testable import Domain

/// Doc 09 « Invariants et tests de propriété » — sept vérités qui doivent tenir pour *toute*
/// partie, pas seulement les cas écrits à la main. `DummyRules` ne fait rien de plus que
/// `GenericSumRules` (Catalog) : elle exerce les mêmes défauts de `GameRules`, sans faire
/// dépendre `DomainTests` de `Catalog`.
private struct DummyRules: GameRules {
    static let engineID = "test.dummy.v1"
}

private func makeDefinition(direction: GameDefinition.Direction = .lowestWins, roundLimit: Int = 1000) -> GameDefinition {
    GameDefinition(
        id: "dummy",
        specVersion: 1,
        rulesVersion: 1,
        name: .init(fr: "Test"),
        symbol: "circle",
        players: .init(min: 2, max: 8),
        scoring: .init(direction: direction, entry: .init(kind: .integer)),
        engine: DummyRules.engineID,
        end: .init(conditions: [.init(type: .roundLimit, value: roundLimit)]),
        tieBreak: [.shared]
    )
}

private func makeParticipants(_ count: Int) -> [Participant] {
    (0 ..< count).map { Participant(displayName: "J\($0)", seatIndex: $0) }
}

private func randomLog(seed: Int, generator: inout SeededGenerator) -> (log: [StampedEvent], catalog: GameCatalog) {
    let participants = makeParticipants(Int.random(in: 2...4, using: &generator))
    let definition = makeDefinition()
    let catalog = try! GameCatalog(definitions: [definition], engineTable: [DummyRules.engineID: { DummyRules() }])

    var events: [StampedEvent] = []
    var lamport: UInt64 = 0
    events.append(StampedEvent(
        lamport: lamport,
        deviceID: "device-a",
        occurredAt: Date(timeIntervalSince1970: 0),
        event: .matchCreated(gameID: "dummy", rulesVersion: 1, variants: VariantSelection(), participants: participants)
    ))

    let roundCount = Int.random(in: 1...8, using: &generator)
    for index in 0..<roundCount {
        lamport += 1
        let inputs = participants.map {
            ScoreInput(participantID: $0.id, rawValue: Int.random(in: -10...10, using: &generator))
        }
        events.append(StampedEvent(
            lamport: lamport,
            deviceID: "device-a",
            occurredAt: Date(timeIntervalSince1970: Double(lamport)),
            event: .roundCommitted(RoundDraft(index: index, inputs: inputs))
        ))
    }
    return (events, catalog)
}

@Suite("Invariants du moteur (doc 09)")
struct EngineInvariantTests {
    @Test("total(joueur) == Σ des computedValue de ses entrées", arguments: 0..<20)
    func totalEqualsSumOfEntries(seed: Int) {
        var generator = SeededGenerator(seed: seed)
        let participants = makeParticipants(Int.random(in: 2...5, using: &generator))
        let definition = makeDefinition()
        let rules = DummyRules()
        let engine = MatchEngine(now: { Date(timeIntervalSince1970: 0) })

        var state = MatchState(matchID: UUID(), gameID: "dummy", rulesVersion: 1, variants: VariantSelection(), participants: participants)
        for index in 0..<Int.random(in: 1...15, using: &generator) {
            let inputs = participants.map {
                ScoreInput(participantID: $0.id, rawValue: Int.random(in: -20...50, using: &generator))
            }
            state = engine.reduce(state, .roundCommitted(RoundDraft(index: index, inputs: inputs)), rules: rules, definition: definition)
        }

        let totals = state.totals()
        for participant in participants {
            let sum = state.rounds.flatMap(\.entries)
                .filter { $0.participantID == participant.id }
                .reduce(0) { $0 + $1.computedValue }
            #expect(totals[participant.id] == sum)
        }
    }

    @Test("standings() est un ordre total cohérent avec le score", arguments: 0..<20)
    func standingsIsATotalOrder(seed: Int) {
        var generator = SeededGenerator(seed: seed)
        let participants = makeParticipants(Int.random(in: 2...6, using: &generator))
        let definition = makeDefinition()
        let rules = DummyRules()
        let engine = MatchEngine(now: { Date(timeIntervalSince1970: 0) })

        var state = MatchState(matchID: UUID(), gameID: "dummy", rulesVersion: 1, variants: VariantSelection(), participants: participants)
        for index in 0..<Int.random(in: 1...10, using: &generator) {
            let inputs = participants.map {
                ScoreInput(participantID: $0.id, rawValue: Int.random(in: -10...30, using: &generator))
            }
            state = engine.reduce(state, .roundCommitted(RoundDraft(index: index, inputs: inputs)), rules: rules, definition: definition)
        }

        let standings = rules.standings(state, definition: definition)
        #expect(standings.count == participants.count, "chaque participant a exactement un classement")
        #expect(Set(standings.map(\.participantID)) == Set(participants.map(\.id)))

        let totals = state.totals()
        for a in standings {
            for b in standings where a.participantID != b.participantID {
                let scoreA = totals[a.participantID] ?? 0
                let scoreB = totals[b.participantID] ?? 0
                if scoreA < scoreB {
                    #expect(a.rank <= b.rank)
                } else if scoreA > scoreB {
                    #expect(a.rank >= b.rank)
                } else {
                    #expect(a.rank == b.rank, "scores égaux ⇒ même rang")
                }
            }
        }
    }

    @Test("endCheck ne repasse jamais de .ended à .continue", arguments: 0..<20)
    func endCheckIsMonotonic(seed: Int) {
        var generator = SeededGenerator(seed: seed)
        let participants = makeParticipants(Int.random(in: 2...4, using: &generator))
        let definition = makeDefinition(roundLimit: 5)
        let rules = DummyRules()
        let engine = MatchEngine(now: { Date(timeIntervalSince1970: 0) })

        var state = MatchState(matchID: UUID(), gameID: "dummy", rulesVersion: 1, variants: VariantSelection(), participants: participants)
        var everEnded = false
        for index in 0..<10 {
            let inputs = participants.map {
                ScoreInput(participantID: $0.id, rawValue: Int.random(in: -5...5, using: &generator))
            }
            state = engine.reduce(state, .roundCommitted(RoundDraft(index: index, inputs: inputs)), rules: rules, definition: definition)
            if state.status == .ended { everEnded = true }
            if everEnded {
                #expect(state.status == .ended, "une fois .ended, ne redevient jamais .continue")
            }
        }
    }

    @Test("Un MatchState encodé puis décodé est identique", arguments: 0..<10)
    func matchStateRoundTripsThroughCodable(seed: Int) throws {
        var generator = SeededGenerator(seed: seed)
        let participants = makeParticipants(Int.random(in: 2...4, using: &generator))
        let definition = makeDefinition()
        let rules = DummyRules()
        let engine = MatchEngine(now: { Date(timeIntervalSince1970: 0) })

        var state = MatchState(
            matchID: UUID(),
            gameID: "dummy",
            rulesVersion: 1,
            variants: VariantSelection(["threshold": .int(100)]),
            participants: participants
        )
        for index in 0..<3 {
            let inputs = participants.map {
                ScoreInput(
                    participantID: $0.id,
                    rawValue: Int.random(in: -5...5, using: &generator),
                    modifiers: index == 0 ? [.closedRound] : []
                )
            }
            state = engine.reduce(state, .roundCommitted(RoundDraft(index: index, inputs: inputs)), rules: rules, definition: definition)
        }

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(MatchState.self, from: data)
        #expect(decoded == state)
    }

    @Test("replay(L) == replay(σ(L)) pour toute permutation σ du journal", arguments: 0..<20)
    func replayIsOrderIndependent(seed: Int) throws {
        var generator = SeededGenerator(seed: seed)
        let (log, catalog) = randomLog(seed: seed, generator: &generator)
        let engine = MatchEngine()

        let baseline = try engine.replay(log, catalog: catalog)
        let shuffled = log.shuffled(using: &generator)
        let result = try engine.replay(shuffled, catalog: catalog)

        #expect(result == baseline)
    }

    @Test("replay(L + L) == replay(L) — idempotence sur les doublons réseau", arguments: 0..<20)
    func replayIsIdempotentUnderDuplication(seed: Int) throws {
        var generator = SeededGenerator(seed: seed)
        let (log, catalog) = randomLog(seed: seed, generator: &generator)
        let engine = MatchEngine()

        let baseline = try engine.replay(log, catalog: catalog)
        let duplicated = try engine.replay(log + log, catalog: catalog)

        #expect(duplicated == baseline)
    }
}
