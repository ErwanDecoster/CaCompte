import Foundation
import SwiftData

/// Doc 02 : les écritures interactives (peu d'objets, latence nulle) restent sur le
/// `mainContext` — pas de `@ModelActor` dédié pour ce volume.
@MainActor
public struct PlayerRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func create(
        nickname: String,
        avatarKind: String,
        avatarValue: String,
        avatarPhoto: Data? = nil,
        paletteID: String? = nil
    ) throws -> PlayerRecord {
        let player = PlayerRecord(
            nickname: nickname,
            avatarKind: avatarKind,
            avatarValue: avatarValue,
            avatarPhoto: avatarPhoto,
            paletteID: paletteID ?? nextAvailablePaletteID(),
            sortIndex: nextSortIndex()
        )
        context.insert(player)
        try context.save()
        return player
    }

    public func save() throws {
        try context.save()
    }

    public func archive(_ player: PlayerRecord) throws {
        player.isArchived = true
        try context.save()
    }

    public func unarchive(_ player: PlayerRecord) throws {
        player.isArchived = false
        try context.save()
    }

    /// Suppression définitive — irréversible, contrairement à `archive`. La règle de suppression
    /// `.nullify` sur `ParticipantRecord.player` (doc 03) garde l'historique lisible : seul le
    /// lien vers la fiche disparaît, les *snapshots* (`nicknameSnapshot`…) restent inchangés.
    public func delete(_ player: PlayerRecord) throws {
        context.delete(player)
        try context.save()
    }

    /// Ordre manuel de la liste des joueurs (`sortIndex`) — SwiftData ne préserve l'ordre
    /// d'aucune collection (doc 03, contrainte CloudKit n°5).
    public func reorder(_ players: [PlayerRecord]) throws {
        for (index, player) in players.enumerated() {
            player.sortIndex = index
        }
        try context.save()
    }

    /// Charte §1.5 : première couleur libre parmi les joueurs actifs à la création. Si les
    /// dix sont prises, reboucle plutôt que d'échouer — l'attribution reste modifiable ensuite.
    public func nextAvailablePaletteID() -> String {
        let active = (try? context.fetch(FetchDescriptor<PlayerRecord>(predicate: #Predicate { !$0.isArchived }))) ?? []
        let used = Set(active.compactMap { Int($0.paletteID) })
        for index in 1...10 where !used.contains(index) {
            return String(index)
        }
        return String((active.count % 10) + 1)
    }

    private func nextSortIndex() -> Int {
        let all = (try? context.fetch(FetchDescriptor<PlayerRecord>())) ?? []
        return (all.map(\.sortIndex).max() ?? -1) + 1
    }
}
