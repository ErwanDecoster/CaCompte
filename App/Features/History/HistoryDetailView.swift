import Catalog
import Domain
import Store
import SwiftData
import SwiftUI

/// Détail d'une partie de l'historique — lecture seule, aucune mutation possible. Rejoue le
/// journal d'événements (doc 04, source de vérité) puis réutilise `ResultsView` telle quelle :
/// podium, faits marquants, courbe et détail manche par manche sont les mêmes qu'à la sortie
/// d'une partie tout juste terminée.
struct HistoryDetailView: View {
    private let state: MatchState
    private let definition: GameDefinition
    private let standings: [Standing]
    private let participantRecords: [ParticipantRecord]

    init(match: MatchRecord, context: ModelContext, catalog: GameCatalog) {
        let repository = MatchRepository(context: context)
        let rules = try! catalog.rules(for: match.gameID, version: match.rulesVersion)
        definition = try! catalog.definition(for: match.gameID, version: match.rulesVersion)
        state = try! repository.loadState(match, catalog: catalog)
        standings = rules.standings(state, definition: definition)
        participantRecords = match.participants.sorted { $0.seatIndex < $1.seatIndex }
    }

    var body: some View {
        ResultsView(
            state: state,
            definition: definition,
            standings: standings,
            participantRecords: participantRecords
        )
    }
}
