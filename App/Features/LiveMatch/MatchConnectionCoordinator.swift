import Catalog
import Domain
import Foundation
import Observation
import Store
import Sync
import UIKit

/// Doc 09 / doc utilisateur P9 — remplace l'ancienne version adossée au Wi-Fi/BLE (voir historique
/// Git : cinq correctifs distincts, tous réels et vérifiés, sans que la connexion ne s'établisse
/// jamais entre deux appareils physiques). Supabase Realtime gère lui-même la reconnexion du
/// websocket/canal (y compris au retour au premier plan), mais seulement à ce niveau-là : ni le
/// rôle négocié, ni l'identité (`hello`/`welcome`), ni les événements manqués pendant la coupure ne
/// sont resynchronisés tout seuls (le broadcast est éphémère, sans rejeu). Ce coordinateur reprend
/// donc la poignée de main applicative en entier — pas seulement le socket — chaque fois qu'un
/// retour au premier plan ou une perte de connexion détectée le justifie (voir `reconnectIfNeeded`
/// et `scheduleAutoRetry`).
///
/// Reste du même patron qu'avant (app-lifetime, comme `DeepLinkRouter.shared`) pour la même
/// raison : à la réouverture après un arrêt complet du processus, SwiftUI ne restaure pas
/// `JoinMatchView` tout seul — la Live Activity ne se remettrait donc jamais à jour tant que
/// l'utilisateur n'a pas manuellement rouvert l'écran de partage.
@MainActor
@Observable
final class MatchConnectionCoordinator {
    static let shared = MatchConnectionCoordinator()

    private(set) var sharedModel: SharedMatchModel?

    private let catalog = GameCatalog.embedded

    /// Doc utilisateur — incrémenté à chaque tentative de connexion (reprise au lancement,
    /// jointure manuelle, reconnexion automatique ou manuelle). Permet à une tentative qui aboutit
    /// après qu'une plus récente a démarré de s'annuler elle-même plutôt que d'écraser le résultat
    /// de celle-ci — sans ça, une reprise auto au lancement sur un code périmé pourrait par
    /// exemple gagner la course contre une jointure manuelle vers une autre partie lancée entre-
    /// temps (les deux appellent `rejoin`, rien ne les sérialise autrement).
    private var attemptGeneration = 0
    private var autoRetryTask: Task<Void, Never>?
    private var foregroundObserver: (any NSObjectProtocol)?

    private init() {
        if let persisted = PersistedSession.load() {
            Task { [weak self] in _ = try? await self?.rejoin(persisted) }
        }
        // Doc utilisateur — remontée : après une mise en arrière-plan assez longue pour que l'OS
        // suspende le processus, le socket Supabase se referme ; à la reprise au premier plan, le
        // SDK le rouvre et réabonne le canal tout seul, mais ne renvoie jamais un `hello` pour
        // nous — sans ce déclencheur explicite, un pair resterait un fantôme anonyme côté hôte
        // (présence expirée, jamais retracée avec le bon rôle) après un simple verrouillage
        // d'écran suivi d'un retour à l'app.
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.reconnectIfNeeded()
            }
        }
    }

    /// Point d'entrée unique pour rejoindre une partie — appelé aussi bien pour la connexion
    /// initiale (`JoinMatchView`) que pour une reconnexion manuelle ou après un relancement.
    @discardableResult
    func join(code: String, deviceName: String, requestedRole: Role, appVersion: String) async throws -> Role {
        try await rejoin(PersistedSession(pairingCode: code, role: requestedRole, deviceName: deviceName, appVersion: appVersion))
    }

    /// « Se reconnecter » manuel (`SharedMatchView`) — un geste immédiat en plus de la reprise
    /// automatique (`scheduleAutoRetry`), pour qui ne veut pas attendre la prochaine tentative.
    @discardableResult
    func reconnectNow() async -> Bool {
        guard let persisted = PersistedSession.load() else { return false }
        return (try? await rejoin(persisted)) != nil
    }

    /// Doc utilisateur — appelé à chaque retour au premier plan tant qu'une partie partagée est
    /// affichée. Toujours un ré-attachement complet (pas seulement « si `isHostConnected` est
    /// faux ») : `isHostConnected` ne reflète que la présence de l'hôte vue par ce pair — si c'est
    /// ce pair lui-même dont la présence a expiré pendant qu'il était en arrière-plan, rien ne le
    /// signale de son côté, il faut donc reprendre la poignée de main dans tous les cas pour être
    /// sûr. Sans effet visible si tout allait déjà bien : l'ancien `sharedModel` reste affiché
    /// jusqu'à ce que le nouveau soit prêt (voir `rejoin`), pas de flash d'écran de chargement.
    private func reconnectIfNeeded() async {
        guard sharedModel != nil else { return }
        _ = await reconnectNow()
    }

    private func rejoin(_ persisted: PersistedSession) async throws -> Role {
        attemptGeneration += 1
        let myGeneration = attemptGeneration

        let transport = SupabaseTransport(deviceID: DeviceIdentity.current, deviceName: persisted.deviceName)
        let host = try await transport.resolveGame(code: persisted.pairingCode)
        let transportSession = try await transport.connect(to: host)
        let liveSession = LiveSession(deviceID: DeviceIdentity.current, catalog: catalog)
        try await liveSession.attachToHost(
            transportSession,
            matchID: host.id,
            pairingCode: persisted.pairingCode,
            requestedRole: persisted.role,
            deviceName: persisted.deviceName,
            appVersion: persisted.appVersion
        )

        // Doc utilisateur — une tentative plus récente (jointure manuelle, reconnexion auto ou
        // manuelle) a démarré pendant que celle-ci était en vol : elle a déjà gagné ou va gagner
        // la course, cette tentative-ci doit se retirer proprement plutôt qu'écraser le résultat.
        guard myGeneration == attemptGeneration else {
            await liveSession.leave()
            throw CancellationError()
        }

        // Doc utilisateur P9 — l'hôte peut assigner un rôle différent de celui demandé
        // (restriction « observateur uniquement ») : `SharedMatchModel` doit refléter le rôle
        // réel, pas le souhait initial.
        let assignedRole = await liveSession.currentRole()
        let previous = sharedModel
        let newModel = SharedMatchModel(session: liveSession, role: assignedRole, catalog: catalog) { [weak self] model in
            self?.scheduleAutoRetry(for: model)
        }
        sharedModel = newModel
        persisted.save()
        await previous?.closeConnection()
        return assignedRole
    }

    /// Doc utilisateur — remontée : le bouton manuel « Se reconnecter » suffisait mais demandait à
    /// l'utilisateur de remarquer la perte et d'agir. Une vraie coupure (hôte parti, réseau perdu)
    /// se rétablit maintenant seule, par tentatives espacées, tant que le modèle affiché est
    /// toujours celui qui a signalé la perte — remplacé (reconnexion réussie par une autre voie) ou
    /// effacé (`stop()`), la boucle s'arrête d'elle-même.
    private func scheduleAutoRetry(for model: SharedMatchModel) {
        guard autoRetryTask == nil else { return }
        autoRetryTask = Task { [weak self, weak model] in
            defer { self?.autoRetryTask = nil }
            while let self, let model, self.sharedModel === model {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                guard self.sharedModel === model else { return }
                if await self.reconnectNow() { return }
            }
        }
    }

    /// Départ volontaire : l'utilisateur quitte réellement la partie (bouton « Quitter »).
    func stop() async {
        autoRetryTask?.cancel()
        autoRetryTask = nil
        attemptGeneration += 1
        await sharedModel?.stop()
        sharedModel = nil
        PersistedSession.clear()
    }
}

/// Ce qu'il faut retenir pour reprendre une partie partagée sans redemander le code d'appairage —
/// survit à un relancement du process (`UserDefaults`, même convention que `DeviceIdentity`).
/// Ne retient pas le `matchID` : `SupabaseTransport.resolveGame(code:)` le résout à nouveau à
/// chaque appel, plus robuste qu'un id mis en cache (le code, lui, redevient invalide de lui-même
/// une fois la partie terminée — voir `SupabaseTransport.stopAdvertising`).
private struct PersistedSession: Codable {
    let pairingCode: String
    let role: Role
    let deviceName: String
    let appVersion: String

    private static let defaultsKey = "MatchConnectionCoordinator.activeSession"

    static func load() -> PersistedSession? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(PersistedSession.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
