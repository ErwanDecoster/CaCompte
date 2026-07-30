import Domain
import Foundation
import Testing
import SwiftData
@testable import Store

private struct DummyRules: GameRules {
    static let engineID = "test.dummy.v1"
}

private func makeCatalog(roundLimit: Int) -> GameCatalog {
    let definition = GameDefinition(
        id: "dummy",
        specVersion: 1,
        rulesVersion: 1,
        name: .init(fr: "Test"),
        symbol: "circle",
        players: .init(min: 2, max: 8),
        scoring: .init(direction: .lowestWins, entry: .init(kind: .integer)),
        engine: DummyRules.engineID,
        end: .init(conditions: [.init(type: .roundLimit, value: roundLimit)]),
        tieBreak: [.shared]
    )
    return try! GameCatalog(definitions: [definition], engineTable: [DummyRules.engineID: { DummyRules() }])
}

@MainActor
@Suite("MatchRepository")
struct MatchRepositoryTests {
    @Test("Une partie se termine, le classement final est écrit, et survit à une réouverture du magasin")
    func matchCompletesAndSurvivesRelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "MatchRepositoryTests-\(UUID()).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema(CaCompteSchemaV1.models)
        let config = ModelConfiguration(schema: schema, url: url)
        let catalog = makeCatalog(roundLimit: 2)

        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            let repository = MatchRepository(context: container.mainContext)
            let seeds = [
                MatchRepository.ParticipantSeed(player: nil, nickname: "Alice", avatarKind: "symbol", avatarValue: "hare.fill", paletteID: "1"),
                MatchRepository.ParticipantSeed(player: nil, nickname: "Bob", avatarKind: "symbol", avatarValue: "tortoise.fill", paletteID: "2"),
            ]
            let match = try repository.createMatch(gameID: "dummy", rulesVersion: 1, variants: VariantSelection(), seeds: seeds)

            let state0 = try repository.loadState(match, catalog: catalog)
            #expect(state0.status == .inProgress)
            let ids = state0.participants.map(\.id)

            try repository.commitRound(
                RoundDraft(index: 0, inputs: ids.map { ScoreInput(participantID: $0, rawValue: 5) }),
                to: match,
                catalog: catalog
            )
            #expect(match.status == .inProgress)

            let finalState = try repository.commitRound(
                RoundDraft(index: 1, inputs: ids.map { ScoreInput(participantID: $0, rawValue: 5) }),
                to: match,
                catalog: catalog
            )
            #expect(finalState.status == .ended)
            #expect(match.status == .ended)
            #expect(match.endedAt != nil)
            #expect(match.participants.allSatisfy { $0.finalRank != nil && $0.finalScore == 10 })
        }

        // Nouveau conteneur, nouveau contexte, même fichier : simule le relaunch de l'app.
        let reopened = try ModelContainer(for: schema, configurations: [config])
        let reloadedMatch = try #require(try reopened.mainContext.fetch(FetchDescriptor<MatchRecord>()).first)
        let repository = MatchRepository(context: reopened.mainContext)
        let reloadedState = try repository.loadState(reloadedMatch, catalog: catalog)

        #expect(reloadedState.status == .ended)
        #expect(reloadedState.rounds.count == 2)
        #expect(reloadedMatch.participants.count == 2)
    }

    @Test("undoLastRound retire la dernière manche et rejoue l'état")
    func undoLastRoundRemovesRound() throws {
        let schema = Schema(CaCompteSchemaV1.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let repository = MatchRepository(context: container.mainContext)
        let catalog = makeCatalog(roundLimit: 1000)

        let seeds = [
            MatchRepository.ParticipantSeed(player: nil, nickname: "Alice", avatarKind: "symbol", avatarValue: "hare.fill", paletteID: "1"),
            MatchRepository.ParticipantSeed(player: nil, nickname: "Bob", avatarKind: "symbol", avatarValue: "tortoise.fill", paletteID: "2"),
        ]
        let match = try repository.createMatch(gameID: "dummy", rulesVersion: 1, variants: VariantSelection(), seeds: seeds)
        let ids = try repository.loadState(match, catalog: catalog).participants.map(\.id)

        try repository.commitRound(RoundDraft(index: 0, inputs: ids.map { ScoreInput(participantID: $0, rawValue: 3) }), to: match, catalog: catalog)
        let afterCommit = try repository.loadState(match, catalog: catalog)
        #expect(afterCommit.rounds.count == 1)

        let afterUndo = try repository.undoLastRound(in: match, catalog: catalog)
        #expect(afterUndo.rounds.isEmpty)
    }

    @Test("endMatchManually termine la partie et écrit le classement final (doc 05 « Jeu libre »)")
    func endMatchManuallyWritesFinalStandings() throws {
        let schema = Schema(CaCompteSchemaV1.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let repository = MatchRepository(context: container.mainContext)
        // roundLimit très haut : seule la fin manuelle peut conclure cette partie.
        let catalog = makeCatalog(roundLimit: 1000)

        let seeds = [
            MatchRepository.ParticipantSeed(player: nil, nickname: "Alice", avatarKind: "symbol", avatarValue: "hare.fill", paletteID: "1"),
            MatchRepository.ParticipantSeed(player: nil, nickname: "Bob", avatarKind: "symbol", avatarValue: "tortoise.fill", paletteID: "2"),
        ]
        let match = try repository.createMatch(gameID: "dummy", rulesVersion: 1, variants: VariantSelection(), seeds: seeds)
        let ids = try repository.loadState(match, catalog: catalog).participants.map(\.id)

        try repository.commitRound(RoundDraft(index: 0, inputs: [
            ScoreInput(participantID: ids[0], rawValue: 5),
            ScoreInput(participantID: ids[1], rawValue: 9),
        ]), to: match, catalog: catalog)
        #expect(match.status == .inProgress)

        let finalState = try repository.endMatchManually(match, catalog: catalog)
        #expect(finalState.status == .ended)
        #expect(finalState.endReason == .manualStop)
        #expect(match.status == .ended)
        #expect(match.endedAt != nil)
        // direction lowestWins (catalogue de test) : Alice (5) devant Bob (9).
        #expect(match.participants.first { $0.nicknameSnapshot == "Alice" }?.finalRank == 1)
        #expect(match.participants.first { $0.nicknameSnapshot == "Bob" }?.finalRank == 2)
    }

    @Test("abandonMatch classe la partie comme abandonnée et écrit quand même un classement final")
    func abandonMatchWritesFinalStandings() throws {
        let schema = Schema(CaCompteSchemaV1.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let repository = MatchRepository(context: container.mainContext)
        let catalog = makeCatalog(roundLimit: 1000)

        let seeds = [
            MatchRepository.ParticipantSeed(player: nil, nickname: "Alice", avatarKind: "symbol", avatarValue: "hare.fill", paletteID: "1"),
            MatchRepository.ParticipantSeed(player: nil, nickname: "Bob", avatarKind: "symbol", avatarValue: "tortoise.fill", paletteID: "2"),
        ]
        let match = try repository.createMatch(gameID: "dummy", rulesVersion: 1, variants: VariantSelection(), seeds: seeds)
        let ids = try repository.loadState(match, catalog: catalog).participants.map(\.id)

        try repository.commitRound(RoundDraft(index: 0, inputs: [
            ScoreInput(participantID: ids[0], rawValue: 5),
            ScoreInput(participantID: ids[1], rawValue: 9),
        ]), to: match, catalog: catalog)

        let finalState = try repository.abandonMatch(match, catalog: catalog)
        #expect(finalState.status == .abandoned)
        #expect(match.status == .abandoned)
        #expect(match.endedAt != nil)
        #expect(match.participants.allSatisfy { $0.finalRank != nil })
        #expect(try repository.inProgressMatches().isEmpty)
    }

    @Test("mostRecentParticipants renvoie les joueurs de la dernière partie terminée de ce jeu, jamais d'une partie en cours")
    func mostRecentParticipantsReturnsLastFinishedMatchOnly() throws {
        let schema = Schema(CaCompteSchemaV1.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let repository = MatchRepository(context: context)
        let catalog = makeCatalog(roundLimit: 1)

        let alice = PlayerRecord(nickname: "Alice", avatarKind: "symbol", avatarValue: "hare.fill", paletteID: "1")
        let bob = PlayerRecord(nickname: "Bob", avatarKind: "symbol", avatarValue: "tortoise.fill", paletteID: "2")
        let chloe = PlayerRecord(nickname: "Chloé", avatarKind: "symbol", avatarValue: "leaf.fill", paletteID: "3")
        [alice, bob, chloe].forEach { context.insert($0) }

        #expect(try repository.mostRecentParticipants(forGameID: "dummy").isEmpty)

        // Première partie terminée : Alice + Bob.
        let firstMatch = try repository.createMatch(
            gameID: "dummy", rulesVersion: 1, variants: VariantSelection(),
            seeds: [
                .init(player: alice, nickname: "Alice", avatarKind: "symbol", avatarValue: "hare.fill", paletteID: "1"),
                .init(player: bob, nickname: "Bob", avatarKind: "symbol", avatarValue: "tortoise.fill", paletteID: "2"),
            ]
        )
        firstMatch.startedAt = Date(timeIntervalSince1970: 0)
        let firstIDs = try repository.loadState(firstMatch, catalog: catalog).participants.map(\.id)
        try repository.commitRound(RoundDraft(index: 0, inputs: firstIDs.map { ScoreInput(participantID: $0, rawValue: 1) }), to: firstMatch, catalog: catalog)
        #expect(firstMatch.status == .ended)

        let afterFirst = try repository.mostRecentParticipants(forGameID: "dummy")
        #expect(afterFirst.map(\.nickname) == ["Alice", "Bob"])

        // Deuxième partie, plus récente : Chloé + Bob. Une troisième partie encore en cours
        // (Alice + Chloé) ne doit jamais influencer le résultat.
        let secondMatch = try repository.createMatch(
            gameID: "dummy", rulesVersion: 1, variants: VariantSelection(),
            seeds: [
                .init(player: chloe, nickname: "Chloé", avatarKind: "symbol", avatarValue: "leaf.fill", paletteID: "3"),
                .init(player: bob, nickname: "Bob", avatarKind: "symbol", avatarValue: "tortoise.fill", paletteID: "2"),
            ]
        )
        secondMatch.startedAt = Date(timeIntervalSince1970: 1000)
        let secondIDs = try repository.loadState(secondMatch, catalog: catalog).participants.map(\.id)
        try repository.commitRound(RoundDraft(index: 0, inputs: secondIDs.map { ScoreInput(participantID: $0, rawValue: 1) }), to: secondMatch, catalog: catalog)
        #expect(secondMatch.status == .ended)

        let thirdMatch = try repository.createMatch(
            gameID: "dummy", rulesVersion: 1, variants: VariantSelection(),
            seeds: [
                .init(player: alice, nickname: "Alice", avatarKind: "symbol", avatarValue: "hare.fill", paletteID: "1"),
                .init(player: chloe, nickname: "Chloé", avatarKind: "symbol", avatarValue: "leaf.fill", paletteID: "3"),
            ]
        )
        thirdMatch.startedAt = Date(timeIntervalSince1970: 2000)
        #expect(thirdMatch.status == .inProgress)

        let afterSecond = try repository.mostRecentParticipants(forGameID: "dummy")
        #expect(afterSecond.map(\.nickname) == ["Chloé", "Bob"])
    }
}
