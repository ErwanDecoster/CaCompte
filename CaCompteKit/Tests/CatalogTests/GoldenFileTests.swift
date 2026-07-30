import Foundation
import Testing
@testable import Catalog
@testable import Domain

/// Doc 09 « Les golden files » — un test paramétré : ajouter un golden au dossier ajoute un
/// cas, sans toucher au code de test. Vérifié après CHAQUE manche, pas seulement à la fin
/// (une erreur qui se compense entre deux manches doit être attrapée).
@Suite("Golden files")
struct GoldenFileTests {
    @Test("Rejeu golden : scores, cumuls, statuts, classement", arguments: GoldenFile.all)
    func replay(_ golden: GoldenFile) throws {
        let catalog = GameCatalog.embedded
        let definition = try catalog.definition(for: golden.gameId, version: golden.rulesVersion)
        let rules = try catalog.rules(for: golden.gameId, version: golden.rulesVersion)

        let idByToken = Dictionary(uniqueKeysWithValues: golden.participants.map { ($0.id, UUID()) })
        let tokenByID = Dictionary(uniqueKeysWithValues: idByToken.map { ($0.value, $0.key) })

        let participants = golden.participants.map {
            Participant(id: idByToken[$0.id]!, displayName: $0.name, seatIndex: $0.seatIndex, teamID: $0.teamID)
        }

        var state = MatchState(
            matchID: UUID(),
            gameID: golden.gameId,
            rulesVersion: golden.rulesVersion,
            variants: golden.variants,
            participants: participants
        )

        // Horloge figée : seul `(lamport, deviceID)` fait foi dans le vrai moteur, mais ici on
        // appelle `reduce` directement (comme le ferait `LiveMatchModel`) — une horloge fixe
        // rend `committedAt` reproductible sans intervenir dans la logique testée.
        let engine = MatchEngine(now: { Date(timeIntervalSince1970: 0) })

        for roundInput in golden.rounds {
            let draft = RoundDraft(
                index: roundInput.index,
                inputs: roundInput.inputs.map { input in
                    ScoreInput(
                        participantID: idByToken[input.participant]!,
                        rawValue: input.rawValue,
                        detail: input.detail.flatMap { detail -> ScoreDetail? in
                            guard let categoryID = detail["categoryID"] else { return nil }
                            return ScoreDetail(payload: try! JSONEncoder().encode(YamsCategoryDetail(categoryID: categoryID)))
                        },
                        modifiers: Set(input.modifiers.map(ModifierID.init(rawValue:)))
                    )
                }
            )
            state = engine.reduce(state, .roundCommitted(draft), rules: rules, definition: definition)

            guard let expectedRound = golden.expected.roundResults.first(where: { $0.index == roundInput.index }) else {
                continue
            }
            guard let actualRound = state.rounds.first(where: { $0.index == roundInput.index }) else {
                Issue.record("\(golden.goldenId) : manche \(roundInput.index) absente de l'état après reduce")
                continue
            }

            for entry in actualRound.entries {
                let token = tokenByID[entry.participantID]!
                #expect(
                    entry.computedValue == expectedRound.computed[token],
                    "\(golden.goldenId) manche \(roundInput.index) — score calculé de \(token)"
                )
                let wasDoubled = entry.computedValue != entry.rawValue
                #expect(
                    wasDoubled == expectedRound.doubled.contains(token),
                    "\(golden.goldenId) manche \(roundInput.index) — doublement de \(token)"
                )
            }

            let cumulative = state.totals()
            for (token, expectedTotal) in expectedRound.cumulative {
                #expect(
                    cumulative[idByToken[token]!] == expectedTotal,
                    "\(golden.goldenId) manche \(roundInput.index) — cumul de \(token)"
                )
            }

            #expect(
                state.status.rawValue == expectedRound.status,
                "\(golden.goldenId) manche \(roundInput.index) — statut"
            )
        }

        #expect(state.status.rawValue == golden.expected.final.status, "\(golden.goldenId) — statut final")

        let standings = rules.standings(state, definition: definition)
        let standingsByToken = Dictionary(uniqueKeysWithValues: standings.map { (tokenByID[$0.participantID]!, $0) })

        for expected in golden.expected.final.standings {
            guard let actual = standingsByToken[expected.participant] else {
                Issue.record("\(golden.goldenId) : classement manquant pour \(expected.participant)")
                continue
            }
            #expect(actual.rank == expected.rank, "\(golden.goldenId) — rang de \(expected.participant)")
            #expect(actual.score == expected.score, "\(golden.goldenId) — score de \(expected.participant)")

            let expectedShared = Set(expected.sharedWith ?? [])
            let actualShared = Set(actual.sharedWith.map { tokenByID[$0]! })
            #expect(
                actualShared == expectedShared,
                "\(golden.goldenId) — partage de rang de \(expected.participant)"
            )
        }

        let candidates = StatsEngine().candidates(state: state, definition: definition)
        let candidatesByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id.rawValue, $0) })

        for expected in golden.expected.insights {
            guard let actual = candidatesByID[expected.id] else {
                Issue.record("\(golden.goldenId) : insight manquant : \(expected.id)")
                continue
            }
            switch actual.value {
            case .single(let participantID, let value, let round):
                if let expectedParticipant = expected.participant {
                    #expect(
                        participantID.map { tokenByID[$0]! } == expectedParticipant,
                        "\(golden.goldenId) — participant de l'insight \(expected.id)"
                    )
                }
                if let expectedValue = expected.value {
                    #expect(
                        abs(value - expectedValue) < 0.01,
                        "\(golden.goldenId) — valeur de l'insight \(expected.id) : \(value) ≠ \(expectedValue)"
                    )
                }
                if let expectedRound = expected.round {
                    #expect(round == expectedRound, "\(golden.goldenId) — manche de l'insight \(expected.id)")
                }
            case .perParticipant(let map):
                if let expectedValues = expected.values {
                    for (token, expectedValue) in expectedValues {
                        #expect(
                            map[idByToken[token]!] == expectedValue,
                            "\(golden.goldenId) — insight \(expected.id) pour \(token) : attendu \(expectedValue)"
                        )
                    }
                }
            }
        }
    }
}
