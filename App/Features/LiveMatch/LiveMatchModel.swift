import Catalog
import Domain
import Foundation
import Store
import SwiftData
import Sync

/// Doc 02 : « il y en a peu : `LiveMatchModel`, `MatchSetupModel`, `PlayerEditorModel`. Ce ne
/// sont pas des ViewModels par écran mais par flux métier. » Porte l'état de la manche en
/// cours ; rien n'est écrit tant qu'elle n'est pas validée (doc 08).
@MainActor
@Observable
final class LiveMatchModel {
    private(set) var state: MatchState {
        didSet { refreshLiveActivity() }
    }

    private(set) var pendingScores: [Participant.ID: Int] = [:]
    var closedParticipantID: Participant.ID?
    private(set) var activeSeatIndex: Int = 0
    private(set) var validationErrorMessage: String?

    let definition: GameDefinition
    private let rules: any GameRules
    private let match: MatchRecord
    private let context: ModelContext
    private let repository: MatchRepository
    private let catalog: GameCatalog

    // MARK: - Doc 09 « Partie partagée » — cet appareil est toujours l'hôte quand il partage,
    // puisque `LiveMatchModel` n'existe que pour une partie qui a un `MatchRecord` local. Un pair
    // qui rejoint utilise `SharedMatchModel`, pas celui-ci. Le partage lui-même est porté par
    // `LiveShareCoordinator` (doc 09 « Fin de partie », révisé) — il survit à ce modèle, qui se
    // recrée à chaque nouvelle partie, plutôt que de mourir avec lui.
    private var shareCoordinator: LiveShareCoordinator { .shared }

    /// Doc utilisateur : sans ça, une manche saisie par un contributeur distant se contente de
    /// faire monter les totaux sans qu'on comprenne pourquoi — l'hôte doit être notifié, pas
    /// seulement voir les chiffres bouger. `nil` la plupart du temps ; la vue l'efface elle-même
    /// après quelques secondes.
    private(set) var remoteActivityMessage: String?
    private var remoteActivityClearTask: Task<Void, Never>?

    /// Doc utilisateur — un score modifié par une règle (doublement Skyjo, bonus…) se contente
    /// autrement de changer silencieusement dans le total : la manche vient d'être validée, c'est
    /// le seul moment où l'explication (`ScoreEntry.explanation`) a une chance d'être vue.
    private(set) var roundExplanationMessage: String?
    private var roundExplanationClearTask: Task<Void, Never>?

    var isSharing: Bool { shareCoordinator.attachedMatchID == match.id }
    var pairingCode: String? { isSharing ? shareCoordinator.pairingCode : nil }
    var connectedPeers: [LiveSession.ConnectedPeer] { isSharing ? shareCoordinator.connectedPeers : [] }

    init(match: MatchRecord, context: ModelContext, catalog: GameCatalog) throws {
        self.match = match
        self.context = context
        self.repository = MatchRepository(context: context)
        self.catalog = catalog
        self.definition = try catalog.definition(for: match.gameID, version: match.rulesVersion)
        self.rules = try catalog.rules(for: match.gameID, version: match.rulesVersion)
        self.state = try repository.loadState(match, catalog: catalog)
        refreshLiveActivity()
        // Doc 09 « Fin de partie » — no-op si aucune session n'est active, no-op si cette partie
        // est déjà attachée ; sinon c'est cet appel qui fait qu'une nouvelle partie rejoint
        // automatiquement une session déjà en cours, sans repasser par « Partager en direct ».
        Task { await LiveShareCoordinator.shared.attach(match: match, context: context) }
    }

    /// Doc 09 « Fin de partie » — donne à `MatchLiveActivityController` la clé d'Activity qui
    /// convient : celle de la session en cours si cette partie lui est attachée (survit à un
    /// changement de partie), sinon celle de la partie elle-même (solo, comportement inchangé).
    private func refreshLiveActivity() {
        MatchLiveActivityController.refresh(
            definition: definition,
            rules: rules,
            state: state,
            isAuthoritative: true,
            sessionID: isSharing ? shareCoordinator.sessionID : nil
        )
    }

    var participants: [Participant] {
        state.participants.sorted { $0.seatIndex < $1.seatIndex }
    }

    var participantRecords: [ParticipantRecord] {
        match.participants.sorted { $0.seatIndex < $1.seatIndex }
    }

    var totals: [Participant.ID: Int] { state.totals() }

    var currentParticipant: Participant? {
        guard participants.indices.contains(activeSeatIndex) else { return nil }
        return participants[activeSeatIndex]
    }

    var isLastParticipant: Bool { activeSeatIndex == participants.count - 1 }
    var actionLabelTitle: LocalizedStringResource { isLastParticipant ? "Valider" : "Suivant" }

    var requiresCloserSelection: Bool {
        definition.scoring.modifiers.contains { $0.kind == .exclusiveFlag && $0.required }
    }

    var finalStandings: [Standing] {
        rules.standings(state, definition: definition)
    }

    /// `.ended` (fin normale) et `.abandoned` (abandon volontaire) affichent tous deux
    /// `ResultsView` — seule une partie encore réellement jouable montre le pavé numérique.
    var isConcluded: Bool {
        state.status == .ended || state.status == .abandoned
    }

    /// Doc 05 « Jeu libre » et tout jeu `manualStop` : la fin ne peut être détectée
    /// automatiquement, elle est proposée dès qu'au moins une manche a été jouée.
    var canEndManually: Bool {
        !state.rounds.isEmpty && definition.end.conditions.contains { $0.type == .manualStop }
    }

    func endManually() {
        state = (try? repository.endMatchManually(match, catalog: catalog, deviceID: DeviceIdentity.current)) ?? state
        syncSharedLogIfNeeded()
    }

    /// Abandon volontaire — classée dans l'historique avec le classement atteint jusque-là,
    /// contrairement à une suppression qui ferait tout perdre.
    func abandon() {
        state = (try? repository.abandonMatch(match, catalog: catalog, deviceID: DeviceIdentity.current)) ?? state
        syncSharedLogIfNeeded()
    }

    func setScore(_ value: Int, for participantID: Participant.ID) {
        pendingScores[participantID] = value
        validationErrorMessage = nil
    }

    func clearScore(for participantID: Participant.ID) {
        pendingScores.removeValue(forKey: participantID)
    }

    /// Le clavier système permet de passer d'un champ à l'autre par un tap direct, pas seulement
    /// via le bouton « Suivant » — l'index courant doit rester synchronisé avec le focus réel.
    func focus(on participantID: Participant.ID) {
        guard let index = participants.firstIndex(where: { $0.id == participantID }) else { return }
        activeSeatIndex = index
    }

    /// `true` si l'avancée a validé et persisté la manche (dernier joueur atteint).
    @discardableResult
    func advance() -> Bool {
        guard isLastParticipant else {
            activeSeatIndex += 1
            return false
        }
        return commitRound()
    }

    @discardableResult
    func commitRound() -> Bool {
        let inputs = participants.map { participant in
            ScoreInput(
                participantID: participant.id,
                rawValue: pendingScores[participant.id] ?? 0,
                modifiers: participant.id == closedParticipantID ? [.closedRound] : []
            )
        }
        let draft = RoundDraft(index: state.rounds.count, inputs: inputs)

        if case .invalid(let errors) = rules.validate(draft, in: state, definition: definition) {
            validationErrorMessage = errors.first?.message
            return false
        }

        do {
            state = try repository.commitRound(draft, to: match, catalog: catalog, deviceID: DeviceIdentity.current)
        } catch {
            validationErrorMessage = "La manche n'a pas pu être enregistrée."
            return false
        }
        pendingScores = [:]
        closedParticipantID = nil
        activeSeatIndex = 0
        validationErrorMessage = nil
        if let explanation = state.rounds.last?.entries.compactMap(\.explanation).first {
            showRoundExplanation(explanation)
        }
        syncSharedLogIfNeeded()
        return true
    }

    private func showRoundExplanation(_ message: String) {
        roundExplanationMessage = message
        roundExplanationClearTask?.cancel()
        roundExplanationClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.roundExplanationMessage = nil
        }
    }

    func undoLastRound() {
        state = (try? repository.undoLastRound(in: match, catalog: catalog, deviceID: DeviceIdentity.current)) ?? state
        syncSharedLogIfNeeded()
    }

    // MARK: - Doc 09 « Partie partagée »

    /// Démarre le partage — ou, si une session est déjà active (une autre partie partagée plus
    /// tôt dans la soirée), y rattache simplement cette partie (`LiveShareCoordinator`). Publie la
    /// partie via Supabase Realtime (`SupabaseTransport`, remplace Wi-Fi/BLE — voir sa doc),
    /// affecte un code d'appairage à 6 chiffres, arbitre les propositions des contributeurs
    /// distants (`LiveSession`). `deviceName` vient de l'appelant (`UIDevice.current.name`) — ni
    /// `Sync` ni `CaCompteKit` ne peuvent lire `UIDevice` (la cible compile aussi pour macOS).
    func startSharing(deviceName: String, allowsContributors: Bool = true) async throws {
        try await shareCoordinator.startSharing(match: match, context: context, deviceName: deviceName, allowsContributors: allowsContributors)
    }

    /// Doc utilisateur P9 — s'applique aux prochaines connexions, pas aux contributeurs déjà
    /// connectés (voir `LiveSession.setAllowsContributors`).
    func setAllowsContributors(_ allowed: Bool) async {
        await shareCoordinator.setAllowsContributors(allowed)
    }

    /// Doc 09 « Fin de partie » — arrête toute la session de partage, pas seulement cette partie :
    /// c'est le seul geste qui la termine désormais (elle ne s'arrête plus automatiquement à la
    /// fin d'une partie).
    func stopSharing() async {
        await shareCoordinator.stopSharing()
    }

    /// Doc 09 « Fin de partie » — `LiveMatchView` appelle ceci sur `.onChange` du jeton republié
    /// par `LiveShareCoordinator` à chaque manche acceptée d'un contributeur distant. Recharge
    /// l'état depuis le repository (déjà persisté par le coordinateur) seulement si l'événement
    /// concerne bien la partie affichée par ce modèle — plusieurs `LiveMatchModel` peuvent
    /// coexister brièvement pendant une transition d'écran, un seul doit réagir.
    func refreshFromRemote() {
        guard shareCoordinator.remoteEventMatchID == match.id,
              let newState = try? repository.loadState(match, catalog: catalog) else { return }
        state = newState
        if shareCoordinator.remoteEventIsRoundCommit, let deviceID = shareCoordinator.remoteEventDeviceID {
            announceIfRemote(deviceID: deviceID)
        }
    }

    /// Doc utilisateur — signale qu'une manche vient d'un contributeur distant plutôt que de
    /// laisser les totaux changer sans explication. `LiveShareCoordinator` ne republie jamais les
    /// propres manches de l'hôte via ce chemin (`session.events` ne porte que les propositions
    /// acceptées d'un pair, jamais les écritures locales), donc pas de filtre à refaire ici.
    private func announceIfRemote(deviceID: String) {
        let name = connectedPeers.first { $0.deviceID == deviceID }?.deviceName ?? "Un appareil"
        remoteActivityMessage = "\(name) a ajouté une manche."
        remoteActivityClearTask?.cancel()
        remoteActivityClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.remoteActivityMessage = nil
        }
    }

    /// Après chaque écriture locale de l'hôte : la session doit refléter le journal réel pour
    /// arbitrer juste, et rediffuser aux pairs connectés ce qui vient d'être ajouté (doc 09). Ne
    /// touche plus jamais à l'arrêt du partage — même si cette écriture conclut la partie (fin
    /// normale, fin manuelle, abandon), la session continue : c'est justement ce qui permet
    /// d'enchaîner sur une autre partie sans se réappairer (doc 09 « Fin de partie », révisé).
    private func syncSharedLogIfNeeded() {
        guard isSharing else { return }
        Task { await shareCoordinator.syncLog(for: match.id) }
    }
}
