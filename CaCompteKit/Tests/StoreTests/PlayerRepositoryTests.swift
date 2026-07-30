import Foundation
import Testing
import SwiftData
@testable import Store

@MainActor
@Suite("PlayerRepository")
struct PlayerRepositoryTests {
    @Test("Dix joueurs créés survivent à une réouverture du magasin (simule un relaunch)")
    func playersSurviveRelaunch() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "PlayerRepositoryTests-\(UUID()).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema(CaCompteSchemaV1.models)
        let config = ModelConfiguration(schema: schema, url: url)

        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            let repository = PlayerRepository(context: container.mainContext)
            for index in 1...10 {
                try repository.create(nickname: "Joueur \(index)", avatarKind: "symbol", avatarValue: "hare.fill")
            }
        }

        // Nouveau conteneur, nouveau contexte, même fichier : simule le relaunch de l'app.
        let reopened = try ModelContainer(for: schema, configurations: [config])
        let players = try reopened.mainContext.fetch(FetchDescriptor<PlayerRecord>())

        #expect(players.count == 10)
        #expect(Set(players.map(\.paletteID)) == Set((1...10).map(String.init)))
    }

    @Test("La palette libre suivante ignore les joueurs archivés")
    func nextAvailablePaletteIDSkipsArchived() throws {
        let schema = Schema(CaCompteSchemaV1.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let repository = PlayerRepository(context: container.mainContext)

        let first = try repository.create(nickname: "Alice", avatarKind: "symbol", avatarValue: "hare.fill")
        #expect(first.paletteID == "1")

        try repository.archive(first)

        let second = try repository.create(nickname: "Bob", avatarKind: "symbol", avatarValue: "tortoise.fill")
        #expect(second.paletteID == "1", "Alice est archivée, la couleur 1 redevient disponible")
    }

    @Test("Le réordonnancement met à jour sortIndex dans l'ordre fourni")
    func reorderUpdatesSortIndex() throws {
        let schema = Schema(CaCompteSchemaV1.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let repository = PlayerRepository(context: container.mainContext)

        let alice = try repository.create(nickname: "Alice", avatarKind: "symbol", avatarValue: "hare.fill")
        let bob = try repository.create(nickname: "Bob", avatarKind: "symbol", avatarValue: "tortoise.fill")
        #expect(alice.sortIndex == 0)
        #expect(bob.sortIndex == 1)

        try repository.reorder([bob, alice])

        #expect(bob.sortIndex == 0)
        #expect(alice.sortIndex == 1)
    }
}
