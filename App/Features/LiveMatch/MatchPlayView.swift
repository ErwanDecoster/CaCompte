import Catalog
import Domain
import Store
import SwiftData
import SwiftUI

/// Point d'aiguillage unique entre les écrans de saisie : `categorySheet` (Yams) a besoin d'une
/// grille dédiée, tout le reste réutilise le pavé numérique de `LiveMatchView`. Centralisé ici
/// pour qu'un futur jeu `structured`/`rank` n'ait qu'un cas à ajouter, à un seul endroit.
struct MatchPlayView: View {
    let match: MatchRecord
    let context: ModelContext
    let catalog: GameCatalog

    var body: some View {
        let definition = try? catalog.definition(for: match.gameID, version: match.rulesVersion)
        Group {
            switch definition?.scoring.entry.kind {
            case .categorySheet:
                YamsSheetView(match: match, context: context, catalog: catalog)
            case .structured:
                BeloteRoundView(match: match, context: context, catalog: catalog)
            default:
                LiveMatchView(match: match, context: context, catalog: catalog)
            }
        }
        .userActivity(MatchContinuation.activityType) { activity in
            MatchContinuation.configure(activity, for: match, gameName: definition?.name.fr)
        }
    }
}
