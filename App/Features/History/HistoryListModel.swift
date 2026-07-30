import Catalog
import Domain
import Foundation
import Store
import SwiftData

@MainActor
@Observable
final class HistoryListModel {
    private(set) var matches: [MatchRecord] = []
    private(set) var archivedCount: Int = 0
    var selectedGameID: String?
    var selectedPlayerID: UUID?

    let catalog: GameCatalog
    private let repository: MatchRepository

    init(context: ModelContext, catalog: GameCatalog) {
        self.repository = MatchRepository(context: context)
        self.catalog = catalog
        reload()
    }

    func reload() {
        matches = (try? repository.finishedMatches()) ?? []
        archivedCount = (try? repository.archivedMatches().count) ?? 0
    }

    func archive(_ match: MatchRecord) {
        try? repository.archive(match)
        reload()
    }

    func archiveMatches(withIDs ids: Set<UUID>) {
        for match in matches where ids.contains(match.id) {
            try? repository.archive(match)
        }
        reload()
    }

    /// Doc 01 « filtrable par jeu et par joueur » — options tirées de l'historique réel, pas du
    /// catalogue complet : inutile de proposer un filtre sur un jeu jamais joué.
    var availableGames: [(id: String, name: String)] {
        let ids = Set(matches.map(\.gameID))
        return ids.compactMap { id in
            (try? catalog.definition(for: id, version: matches.first { $0.gameID == id }?.rulesVersion ?? 1))
                .map { (id: id, name: $0.name.fr) } ?? (id: id, name: id)
        }.sorted { $0.name < $1.name }
    }

    /// La suppression d'une fiche joueur annule `participant.player` (règle `.nullify`, doc 03) mais
    /// garde `nicknameSnapshot` — les parties passées restent dans l'historique. Le filtre doit donc
    /// lister les joueurs tels qu'ils apparaissent dans les parties, pas la liste des fiches encore
    /// existantes : on retombe sur l'id du participant quand la fiche a été supprimée.
    var availablePlayers: [(id: UUID, name: String)] {
        var byID: [UUID: String] = [:]
        for match in matches {
            for participant in match.participants {
                byID[participant.player?.id ?? participant.id] = participant.nicknameSnapshot
            }
        }
        return byID.map { (id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
    }

    var filteredMatches: [MatchRecord] {
        matches.filter { match in
            (selectedGameID == nil || match.gameID == selectedGameID)
                && (selectedPlayerID == nil || match.participants.contains {
                    ($0.player?.id ?? $0.id) == selectedPlayerID
                })
        }
    }

    func gameName(for match: MatchRecord) -> String {
        (try? catalog.definition(for: match.gameID, version: match.rulesVersion))?.name.fr ?? match.gameID
    }

    func gameSymbol(for match: MatchRecord) -> String {
        (try? catalog.definition(for: match.gameID, version: match.rulesVersion))?.symbol ?? "circle"
    }

    func winner(for match: MatchRecord) -> ParticipantRecord? {
        match.participants.first { $0.finalRank == 1 }
    }
}
