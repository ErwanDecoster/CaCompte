import Domain
import Foundation
import Sync

/// Doc 09 — pendant de `LiveMatchModel` pour un pair non-hôte : pas de `MatchRecord` local, pas
/// de `MatchRepository` (seul l'hôte persiste, doc 09 « hôte autoritaire »). L'état est
/// entièrement reconstruit à chaque événement reçu via `MatchEngine.replay` — un rejeu complet
/// coûte moins d'une milliseconde pour une partie normale (doc 04/ADR-0005), la complexité d'une
/// réduction incrémentale ne se justifie pas ici.
@MainActor
@Observable
final class SharedMatchModel {
    private(set) var state: MatchState?
    private(set) var definition: GameDefinition?
    private var rules: (any GameRules)?
    private(set) var latestRejectionReason: String?
    /// Doc utilisateur — même bandeau que côté hôte (`LiveMatchModel.roundExplanationMessage`)
    /// quand une règle modifie un score saisi (doublement Skyjo…) : recalculé localement par le
    /// rejeu (`engine.replay`), donc visible ici aussi bien que sur l'appareil de l'hôte.
    private(set) var roundExplanationMessage: String?
    private var roundExplanationClearTask: Task<Void, Never>?
    /// Doc 09 — l'hôte a arrêté le partage ou la connexion a été perdue. La partie continue de
    /// s'afficher (dernier état connu), mais aucune nouvelle manche ne peut plus être proposée.
    private(set) var isHostConnected = true

    let role: Role

    private let catalog: GameCatalog
    private let engine = MatchEngine()
    private let session: LiveSession
    private var log: [StampedEvent] = []
    private var tasks: [Task<Void, Never>] = []

    var participants: [Participant] {
        state?.participants.sorted { $0.seatIndex < $1.seatIndex } ?? []
    }

    var totals: [Participant.ID: Int] { state?.totals() ?? [:] }

    /// Doc 09 — distingue « la partie est terminée » (fin normale attendue, l'hôte a arrêté le
    /// partage juste après) d'une vraie perte de connexion, pour ne pas afficher la même alarme
    /// dans les deux cas alors qu'un seul est un problème.
    var isConcluded: Bool { state?.status == .ended || state?.status == .abandoned }

    /// Doc 09 — seul un contributeur peut proposer une manche ; un observateur reste en lecture.
    var canPropose: Bool { role == .contributor }

    /// Doc utilisateur P9 — appelé (avec `self`) depuis l'unique tâche qui consomme déjà
    /// `session.hostLeft` ci-dessous, jamais par un second abonnement séparé : `AsyncStream` ne
    /// livre chaque valeur qu'à un seul consommateur, et un second `for await` en parallèle sur
    /// le même flux en avait déjà privé un abonné plus tôt (bug BLE-era, voir historique Git).
    /// `MatchConnectionCoordinator` s'en sert pour déclencher une reprise automatique sans dupliquer
    /// l'abonnement.
    init(session: LiveSession, role: Role, catalog: GameCatalog, onHostLeft: ((SharedMatchModel) -> Void)? = nil) {
        self.session = session
        self.role = role
        self.catalog = catalog

        let eventsTask = Task { [weak self] in
            for await stamped in session.events {
                self?.apply(stamped)
            }
        }
        let rejectionsTask = Task { [weak self] in
            for await rejection in session.rejections {
                self?.handleRejection(eventID: rejection.eventID, reason: rejection.reason)
            }
        }
        let hostLeftTask = Task { [weak self] in
            for await _ in session.hostLeft {
                guard let self else { return }
                self.isHostConnected = false
                // Doc utilisateur — remontée : l'écran verrouillé continuait d'afficher le
                // dernier score reçu sans rien signaler, comme s'il était toujours à jour.
                if let matchID = self.state?.matchID {
                    MatchLiveActivityController.markStale(matchID: matchID)
                }
                onHostLeft?(self)
            }
        }
        tasks = [eventsTask, rejectionsTask, hostLeftTask]
    }

    func propose(_ inputs: [ScoreInput], note: String? = nil) async {
        guard canPropose, let state else { return }
        let draft = RoundDraft(index: state.rounds.count, inputs: inputs, note: note)
        latestRejectionReason = nil
        try? await session.propose(.roundCommitted(draft))
    }

    /// Départ volontaire de l'écran : prévient l'hôte et ferme la connexion (`LiveSession.leave`)
    /// avant d'arrêter d'écouter — sans cet ordre, l'hôte continuerait de nous lister comme
    /// connecté (même bug que `LiveMatchModel.stopSharing`, côté pair cette fois). Termine aussi
    /// la Live Activity : contrairement à `closeConnection()`, ceci veut dire « je ne suis plus
    /// cette partie », pas « je change juste de transport ».
    func stop() async {
        if let matchID = state?.matchID {
            MatchLiveActivityController.stopTracking(matchID: matchID)
        }
        await closeConnection()
    }

    /// Doc utilisateur P9 — ferme la connexion transport sans toucher à la Live Activity : utilisé
    /// quand `MatchConnectionCoordinator` remplace cette session par une nouvelle (reconnexion),
    /// où l'utilisateur n'a pas quitté la partie, seule la connexion sous-jacente change.
    func closeConnection() async {
        await session.leave()
        for task in tasks { task.cancel() }
        tasks = []
    }

    private func apply(_ stamped: StampedEvent) {
        // Doc 04 « Event sourcing » — dédoublonnage par id : la confirmation d'une proposition
        // optimiste porte le même id qu'elle (doc 09), l'ajouter une seconde fois ne changerait
        // rien au résultat, mais autant éviter de faire grossir le journal pour rien.
        guard !log.contains(where: { $0.id == stamped.id }) else { return }
        log.append(stamped)
        guard let replayed = try? engine.replay(log, catalog: catalog) else { return }
        state = replayed
        definition = try? catalog.definition(for: replayed.gameID, version: replayed.rulesVersion)
        rules = try? catalog.rules(for: replayed.gameID, version: replayed.rulesVersion)

        if case .roundCommitted = stamped.event, let explanation = replayed.rounds.last?.entries.compactMap(\.explanation).first {
            roundExplanationMessage = explanation
            roundExplanationClearTask?.cancel()
            roundExplanationClearTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                self?.roundExplanationMessage = nil
            }
        }

        if let definition, let rules {
            MatchLiveActivityController.refresh(definition: definition, rules: rules, state: replayed)
        }
    }

    /// Doc 09 — « le contributeur applique optimistement l'événement en local et l'annule si une
    /// `rejection` arrive » : la seconde moitié de cette phrase n'était jamais faite. Un rejet
    /// se contentait d'afficher un message d'erreur sans jamais retirer la manche déjà affichée
    /// comme validée — la validation par l'hôte semblait donc ne rien changer.
    private func handleRejection(eventID: UUID, reason: String) {
        latestRejectionReason = reason
        log.removeAll { $0.id == eventID }
        guard let replayed = try? engine.replay(log, catalog: catalog) else { return }
        state = replayed
    }
}
