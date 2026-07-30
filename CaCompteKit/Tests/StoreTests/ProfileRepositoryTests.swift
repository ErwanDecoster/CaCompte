import Domain
import Foundation
import Testing
import SwiftData
@testable import Store

private struct DummyRules: GameRules {
    static let engineID = "test.dummy.v1"
}

private func makeDefinition(id: String, direction: Direction, roundLimit: Int) -> GameDefinition {
    GameDefinition(
        id: id,
        specVersion: 1,
        rulesVersion: 1,
        name: .init(fr: id.capitalized),
        symbol: "circle",
        players: .init(min: 2, max: 8),
        scoring: .init(direction: direction, entry: .init(kind: .integer)),
        engine: DummyRules.engineID,
        end: .init(conditions: [.init(type: .roundLimit, value: roundLimit)]),
        tieBreak: [.shared]
    )
}

private func makeCatalog(_ definitions: [GameDefinition]) -> GameCatalog {
    try! GameCatalog(definitions: definitions, engineTable: [DummyRules.engineID: { DummyRules() }])
}

@MainActor
@Suite("ProfileRepository", .serialized)
struct ProfileRepositoryTests {
    /// Joue une partie à deux manches et retourne le `MatchRecord` terminé — `scores` associe
    /// chaque joueur à ses valeurs de manche 1 et 2 (le total, avec `direction: .lowestWins`,
    /// détermine le rang : le plus petit gagne).
    @discardableResult
    private func playMatch(
        gameID: String,
        players: [PlayerRecord],
        scores: [UUID: (Int, Int)],
        catalog: GameCatalog,
        startedAt: Date,
        context: ModelContext
    ) throws -> MatchRecord {
        let repository = MatchRepository(context: context)
        let seeds = players.map { player in
            MatchRepository.ParticipantSeed(
                player: player, nickname: player.nickname, avatarKind: "symbol",
                avatarValue: "circle", paletteID: "1"
            )
        }
        let match = try repository.createMatch(gameID: gameID, rulesVersion: 1, variants: VariantSelection(), seeds: seeds)
        match.startedAt = startedAt

        let state0 = try repository.loadState(match, catalog: catalog)
        let idByPlayerID = Dictionary(uniqueKeysWithValues: zip(players.map(\.id), state0.participants.map(\.id)))

        for round in 0..<2 {
            let inputs = players.map { player in
                let values = scores[player.id] ?? (0, 0)
                let value = round == 0 ? values.0 : values.1
                return ScoreInput(participantID: idByPlayerID[player.id]!, rawValue: value)
            }
            try repository.commitRound(RoundDraft(index: round, inputs: inputs), to: match, catalog: catalog)
        }
        try context.save()
        return match
    }

    /// Le `ModelContainer` doit rester vivant pour toute la durée du test — un contexte dont le
    /// container a été désalloué plante au premier accès (d'où le retour du container ici, pas
    /// seulement de son `mainContext`).
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(CaCompteSchemaV1.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("Aucune partie terminée : statistiques vides")
    func emptyWhenNoFinishedMatch() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let alice = PlayerRecord(nickname: "Alice", avatarKind: "symbol", avatarValue: "circle", paletteID: "1")
        context.insert(alice)
        try context.save()

        let stats = try ProfileRepository(context: context).stats(for: alice, catalog: makeCatalog([]))
        #expect(stats == .empty)
    }

    @Test("Parties jouées, victoires, rang moyen et rang normalisé sur plusieurs parties")
    func aggregatesAcrossMatches() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let catalog = makeCatalog([makeDefinition(id: "dummy", direction: .lowestWins, roundLimit: 2)])

        let alice = PlayerRecord(nickname: "Alice", avatarKind: "symbol", avatarValue: "circle", paletteID: "1")
        let bob = PlayerRecord(nickname: "Bob", avatarKind: "symbol", avatarValue: "circle", paletteID: "2")
        let carol = PlayerRecord(nickname: "Carol", avatarKind: "symbol", avatarValue: "circle", paletteID: "3")
        [alice, bob, carol].forEach { context.insert($0) }

        let now = Date()
        // Alice bat Bob 4 fois sur 6 (rang 1 = plus petit total, direction lowestWins).
        for index in 0..<6 {
            let aliceWins = index % 3 != 2 // gagne aux index 0,1,3,4 ; perd à 2 et 5 → 4/6
            try playMatch(
                gameID: "dummy", players: [alice, bob],
                scores: [alice.id: aliceWins ? (1, 1) : (9, 9), bob.id: aliceWins ? (9, 9) : (1, 1)],
                catalog: catalog, startedAt: now, context: context
            )
        }
        // Alice bat Carol 1 fois sur 5 seulement → nemesis.
        for index in 0..<5 {
            let aliceWins = index == 0
            try playMatch(
                gameID: "dummy", players: [alice, carol],
                scores: [alice.id: aliceWins ? (1, 1) : (9, 9), carol.id: aliceWins ? (9, 9) : (1, 1)],
                catalog: catalog, startedAt: now, context: context
            )
        }

        let stats = try ProfileRepository(context: context).stats(for: alice, catalog: catalog)
        #expect(stats.played == 11)
        #expect(stats.wins == 5)
        #expect(abs(stats.winRate - 5.0 / 11.0) < 0.0001)
        // Rang 1 cinq fois (les victoires), rang 2 six fois (les défaites, 2 joueurs, pas d'ex æquo).
        #expect(abs(stats.averageRank - (5.0 * 1 + 6.0 * 2) / 11.0) < 0.0001)
        // À 2 joueurs, le rang normalisé vaut 1 pour une victoire, 0 pour une défaite.
        #expect(abs(stats.averageNormalizedRank - 5.0 / 11.0) < 0.0001)

        let nemesis = try #require(stats.nemesis)
        #expect(nemesis.playerID == carol.id)
        #expect(nemesis.matchesTogether == 5)
        #expect(abs(nemesis.winRateWithThemPresent - 1.0 / 5.0) < 0.0001)
    }

    @Test("Le meilleur et le pire score personnel respectent le sens du jeu")
    func bestAndWorstScoreRespectDirection() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let lowestWins = makeDefinition(id: "golf", direction: .lowestWins, roundLimit: 2)
        let highestWins = makeDefinition(id: "points", direction: .highestWins, roundLimit: 2)
        let catalog = makeCatalog([lowestWins, highestWins])

        let alice = PlayerRecord(nickname: "Alice", avatarKind: "symbol", avatarValue: "circle", paletteID: "1")
        let bob = PlayerRecord(nickname: "Bob", avatarKind: "symbol", avatarValue: "circle", paletteID: "2")
        [alice, bob].forEach { context.insert($0) }

        try playMatch(gameID: "golf", players: [alice, bob], scores: [alice.id: (2, 3), bob.id: (9, 9)], catalog: catalog, startedAt: Date(), context: context)
        try playMatch(gameID: "golf", players: [alice, bob], scores: [alice.id: (10, 10), bob.id: (1, 1)], catalog: catalog, startedAt: Date(), context: context)
        try playMatch(gameID: "points", players: [alice, bob], scores: [alice.id: (10, 10), bob.id: (1, 1)], catalog: catalog, startedAt: Date(), context: context)
        try playMatch(gameID: "points", players: [alice, bob], scores: [alice.id: (1, 1), bob.id: (10, 10)], catalog: catalog, startedAt: Date(), context: context)

        let stats = try ProfileRepository(context: context).stats(for: alice, catalog: catalog)
        let golf = try #require(stats.byGame.first { $0.gameID == "golf" })
        // lowestWins : le meilleur score personnel est le plus bas.
        #expect(golf.bestScore?.value == 5)
        #expect(golf.worstScore?.value == 20)

        let points = try #require(stats.byGame.first { $0.gameID == "points" })
        // highestWins : le meilleur score personnel est le plus haut.
        #expect(points.bestScore?.value == 20)
        #expect(points.worstScore?.value == 2)
    }

    @Test("L'activité mensuelle recense les 12 derniers mois, à zéro s'il n'y a rien")
    func monthlyActivityZeroFillsEmptyMonths() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let catalog = makeCatalog([makeDefinition(id: "dummy", direction: .lowestWins, roundLimit: 2)])

        let alice = PlayerRecord(nickname: "Alice", avatarKind: "symbol", avatarValue: "circle", paletteID: "1")
        let bob = PlayerRecord(nickname: "Bob", avatarKind: "symbol", avatarValue: "circle", paletteID: "2")
        [alice, bob].forEach { context.insert($0) }

        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        let twoMonthsAgo = calendar.date(byAdding: .month, value: -2, to: now)!

        try playMatch(gameID: "dummy", players: [alice, bob], scores: [alice.id: (1, 1), bob.id: (9, 9)], catalog: catalog, startedAt: twoMonthsAgo, context: context)
        try playMatch(gameID: "dummy", players: [alice, bob], scores: [alice.id: (1, 1), bob.id: (9, 9)], catalog: catalog, startedAt: twoMonthsAgo, context: context)

        let stats = try ProfileRepository(context: context).stats(for: alice, catalog: catalog)
        #expect(stats.activity.count == 12)
        #expect(stats.activity.last?.count == 0) // le mois courant n'a pas de partie
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let expectedKey = formatter.string(from: twoMonthsAgo)
        #expect(stats.activity.first { $0.monthKey == expectedKey }?.count == 2)
    }
}
