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
        didSet { MatchLiveActivityController.refresh(definition: definition, rules: rules, state: state) }
    }

    private(set) var pendingScores: [Participant.ID: Int] = [:]
    var closedParticipantID: Participant.ID?
    private(set) var activeSeatIndex: Int = 0
    private(set) var validationErrorMessage: String?

    let definition: GameDefinition
    private let rules: any GameRules
    private let match: MatchRecord
    private let repository: MatchRepository
    private let catalog: GameCatalog

    // MARK: - Doc 09 « Partie partagée » — cet appareil est toujours l'hôte quand il partage,
    // puisque `LiveMatchModel` n'existe que pour une partie qui a un `MatchRecord` local. Un pair
    // qui rejoint utilise `SharedMatchModel`, pas celui-ci.
    private(set) var pairingCode: String?
    private(set) var connectedPeers: [LiveSession.ConnectedPeer] = []
    private var session: LiveSession?
    private var transport: WifiTransport?
    /// Doc utilisateur P9 — annoncée en plus du Wi-Fi pendant toute la session de partage, pas
    /// seulement en secours de découverte (doc 09/ADR-0014 d'origine) : un pair déjà connecté qui
    /// bascule sur Bluetooth au passage en arrière-plan (`JoinMatchView`, connexion Wi-Fi qui
    /// meurt sans entitlement réseau en tâche de fond) a besoin de nous trouver là aussi.
    private var bleTransport: BLETransport?
    private var sharingTasks: [Task<Void, Never>] = []

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

    var isSharing: Bool { session != nil }

    init(match: MatchRecord, context: ModelContext, catalog: GameCatalog) throws {
        self.match = match
        self.repository = MatchRepository(context: context)
        self.catalog = catalog
        self.definition = try catalog.definition(for: match.gameID, version: match.rulesVersion)
        self.rules = try catalog.rules(for: match.gameID, version: match.rulesVersion)
        self.state = try repository.loadState(match, catalog: catalog)
        MatchLiveActivityController.refresh(definition: definition, rules: rules, state: state)
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

    /// Démarre le partage : annonce sur Wi-Fi (`WifiTransport`, ADR-0014), affecte un code
    /// d'appairage à 6 chiffres, arbitre les propositions des contributeurs distants
    /// (`LiveSession`). `deviceName` vient de l'appelant (`UIDevice.current.name`) — ni `Sync`
    /// ni `CaCompteKit` ne peuvent lire `UIDevice` (la cible compile aussi pour macOS).
    func startSharing(deviceName: String, allowsContributors: Bool = true) async throws {
        let newSession = LiveSession(deviceID: DeviceIdentity.current, catalog: catalog)
        let code = LiveSession.generatePairingCode()
        try await newSession.startHosting(log: repository.currentLog(for: match), pairingCode: code, allowsContributors: allowsContributors)

        let newTransport = WifiTransport(deviceName: deviceName)
        try await newTransport.advertise(matchID: state.matchID, gameID: match.gameID, participantCount: participants.count)

        // Doc utilisateur P9 — best-effort : le Wi-Fi ci-dessus est le chemin testé et déjà
        // confirmé au moment où on arrive ici, l'échec du Bluetooth (désactivé, non autorisé) ne
        // doit pas empêcher le partage de démarrer.
        let newBLETransport = BLETransport(deviceName: deviceName)
        try? await newBLETransport.advertise(matchID: state.matchID, gameID: match.gameID, participantCount: participants.count)

        session = newSession
        transport = newTransport
        bleTransport = newBLETransport
        pairingCode = code

        let acceptTask = Task { [weak self] in
            for await incoming in newTransport.acceptIncoming() {
                guard self != nil else { return }
                await newSession.acceptConnection(incoming)
            }
        }
        let bleAcceptTask = Task { [weak self] in
            for await incoming in newBLETransport.acceptIncoming() {
                guard self != nil else { return }
                await newSession.acceptConnection(incoming)
            }
        }
        let eventsTask = Task { [weak self] in
            for await stamped in newSession.events {
                guard let self else { return }
                if let newState = try? self.repository.appendRemoteEvent(stamped, to: self.match, catalog: self.catalog) {
                    self.state = newState
                    self.announceIfRemote(stamped)
                }
            }
        }
        let peersTask = Task { [weak self] in
            for await peers in newSession.peerUpdates {
                self?.connectedPeers = peers
            }
        }
        sharingTasks = [acceptTask, bleAcceptTask, eventsTask, peersTask]
    }

    /// Doc utilisateur P9 — s'applique aux prochaines connexions, pas aux contributeurs déjà
    /// connectés (voir `LiveSession.setAllowsContributors`).
    func setAllowsContributors(_ allowed: Bool) async {
        await session?.setAllowsContributors(allowed)
    }

    func stopSharing() async {
        // Doit fermer réellement chaque connexion pair (pas seulement oublier la référence
        // locale) : sans ça, un pair resterait indéfiniment listé comme connecté chez lui-même,
        // faute d'avoir jamais vu son socket se fermer (bug observé en recette).
        await session?.stopHosting()
        for task in sharingTasks { task.cancel() }
        sharingTasks = []
        await transport?.stopAdvertising()
        transport = nil
        await bleTransport?.stopAdvertising()
        bleTransport = nil
        session = nil
        pairingCode = nil
        connectedPeers = []
    }

    /// Doc utilisateur — signale qu'une manche vient d'un contributeur distant plutôt que de
    /// laisser les totaux changer sans explication. Ignore les événements qui viennent de cet
    /// appareil lui-même (ses propres manches n'ont pas besoin de s'auto-annoncer).
    private func announceIfRemote(_ stamped: StampedEvent) {
        guard case .roundCommitted = stamped.event else { return }
        guard stamped.deviceID != DeviceIdentity.current else { return }
        let name = connectedPeers.first { $0.deviceID == stamped.deviceID }?.deviceName ?? "Un appareil"
        remoteActivityMessage = "\(name) a ajouté une manche."
        remoteActivityClearTask?.cancel()
        remoteActivityClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.remoteActivityMessage = nil
        }
    }

    /// Après chaque écriture locale de l'hôte : `LiveSession` doit refléter le journal réel pour
    /// arbitrer juste, et rediffuser aux pairs connectés ce qui vient d'être ajouté (doc 09).
    /// Si cette écriture conclut la partie (fin normale, fin manuelle, abandon), le partage
    /// s'arrête automatiquement une fois la diffusion faite : sans ça, l'hôte continuait
    /// d'annoncer une partie terminée, toujours visible et rejoignable depuis un autre appareil
    /// (bug observé en recette), et les pairs restaient connectés à une partie qui n'existe plus.
    private func syncSharedLogIfNeeded() {
        guard let session else { return }
        guard let log = try? repository.currentLog(for: match) else { return }
        let matchJustConcluded = isConcluded
        Task {
            try? await session.syncHostLog(log)
            if matchJustConcluded {
                await self.stopSharing()
            }
        }
    }
}
