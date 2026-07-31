import Catalog
import Domain
import Foundation
import Observation
import Store
import Sync

/// Doc 09 / doc utilisateur P9 — remplace l'ancienne version adossée au Wi-Fi/BLE (voir historique
/// Git : cinq correctifs distincts, tous réels et vérifiés, sans que la connexion ne s'établisse
/// jamais entre deux appareils physiques). Supabase Realtime gère lui-même la reconnexion du
/// websocket et le rejoin des canaux (y compris au retour au premier plan) — il n'y a donc plus de
/// logique de reconnexion à écrire à la main ici, contrairement à l'ancienne version.
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

    private init() {
        if let persisted = PersistedSession.load() {
            Task { [weak self] in _ = try? await self?.rejoin(persisted) }
        }
    }

    /// Point d'entrée unique pour rejoindre une partie — appelé aussi bien pour la connexion
    /// initiale (`JoinMatchView`) que pour une reconnexion manuelle ou après un relancement.
    @discardableResult
    func join(code: String, deviceName: String, requestedRole: Role, appVersion: String) async throws -> Role {
        try await rejoin(PersistedSession(pairingCode: code, role: requestedRole, deviceName: deviceName, appVersion: appVersion))
    }

    /// « Se reconnecter » manuel (`SharedMatchView`) : reprend depuis zéro (nouvelle résolution du
    /// code, nouvelle connexion). Le SDK Supabase se reconnecte déjà tout seul pour toute coupure
    /// passagère — si ce bouton est visible, c'est qu'une reconnexion automatique n'a pas suffi
    /// (hôte réellement arrêté, ou coupure prolongée), donc repartir de zéro est le bon geste.
    @discardableResult
    func reconnectNow() async -> Bool {
        guard let persisted = PersistedSession.load() else { return false }
        return (try? await rejoin(persisted)) != nil
    }

    private func rejoin(_ persisted: PersistedSession) async throws -> Role {
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
        // Doc utilisateur P9 — l'hôte peut assigner un rôle différent de celui demandé
        // (restriction « observateur uniquement ») : `SharedMatchModel` doit refléter le rôle
        // réel, pas le souhait initial.
        let assignedRole = await liveSession.currentRole()
        let previous = sharedModel
        sharedModel = SharedMatchModel(session: liveSession, role: assignedRole, catalog: catalog)
        persisted.save()
        await previous?.closeConnection()
        return assignedRole
    }

    /// Départ volontaire : l'utilisateur quitte réellement la partie (bouton « Quitter »).
    func stop() async {
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
