import Catalog
import DesignSystem
import Domain
import Store
import Sync
import SwiftUI
import UIKit

/// Doc 09 — écran « Rejoindre une partie » : découverte Wi-Fi (`WifiTransport.discover`),
/// appairage par code, puis bascule vers `SharedMatchView` une fois connecté. Une seule feuille
/// porte tout le parcours plutôt que d'enchaîner plusieurs présentations — plus simple à défaire
/// si la connexion échoue (on reste sur la liste de découverte).
struct JoinMatchView: View {
    let catalog: GameCatalog

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var transport = WifiTransport(deviceName: UIDevice.current.name)
    /// Doc utilisateur P9 — secours de `transport` : découverte/reconnexion (`reconnect()`) et
    /// bascule automatique au passage en arrière-plan (`beginBLEHandoverIfNeeded()`). L'hôte
    /// annonce en Bluetooth en plus du Wi-Fi pendant toute la session de partage
    /// (`LiveMatchModel.startSharing`), donc toujours joignable ici.
    @State private var bleTransport = BLETransport(deviceName: UIDevice.current.name)
    @State private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    @State private var handoverRetryTask: Task<Void, Never>?
    /// Doc utilisateur P9 — remontée (recette physique : connexion qui se rétablit puis casse
    /// aussitôt, aucune manche ne passe jamais) : `BLECentralDelegate` garde son état de connexion
    /// en cours dans des propriétés à emplacement unique (`connectContinuation`, `activeSession`,
    /// `discoveryContinuation`) — pas conçu pour deux tentatives en vol en même temps. Depuis que
    /// la reconnexion se déclenche aussi automatiquement (`isHostConnected` qui passe à `false`),
    /// rien n'empêchait ce déclenchement de chevaucher un appui manuel sur « Se reconnecter », ou
    /// de se chevaucher avec lui-même : chacun écrase l'état de l'autre au même endroit,
    /// corrompant laquelle des deux tentatives reçoit effectivement la session résolue.
    @State private var isAttemptingConnection = false
    @State private var discoveredHosts: [DiscoveredHost] = []
    @State private var hostAwaitingCode: DiscoveredHost?
    @State private var pairingCode = ""
    /// Doc utilisateur — le code venu d'un QR ou d'un lien `cacompte://` est déjà connu : la
    /// feuille d'appairage saute directement au choix du rôle, sans (re)demander sa saisie.
    @State private var isCodePrefilled = false
    @State private var selectedRole: Role = .observer
    @State private var isConnecting = false
    @State private var connectionError: String?
    @State private var sharedModel: SharedMatchModel?
    /// Doc utilisateur — retenu après une connexion réussie, pour une reconnexion (`reconnect()`)
    /// sans redemander le code : l'app en arrière-plan coupe la connexion Wi-Fi (pas
    /// d'entitlement réseau en tâche de fond), remontée comme perte totale de la partie.
    @State private var connectedMatchID: UUID?
    @State private var discoveryTask: Task<Void, Never>?
    @State private var wifiAvailability = WiFiAvailability()
    @State private var isPresentingScanner = false
    /// Doc utilisateur — code scanné (ou reçu par lien `cacompte://`) en attente d'un hôte
    /// correspondant. La découverte Wi-Fi reste indispensable : un QR ne fait que remplacer la
    /// frappe des 6 chiffres, jamais la résolution réseau elle-même.
    @State private var pendingJoinPayload: JoinLink.Payload?

    init(catalog: GameCatalog, initialPayload: JoinLink.Payload? = nil) {
        self.catalog = catalog
        _pendingJoinPayload = State(initialValue: initialPayload)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let sharedModel {
                    SharedMatchView(model: sharedModel, onReconnect: reconnect)
                } else {
                    discoveryList
                }
            }
            .navigationTitle("Rejoindre une partie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sharedModel == nil ? "Fermer" : "Quitter") {
                        Task {
                            await sharedModel?.stop()
                            dismiss()
                        }
                    }
                }
            }
        }
        .task {
            discoveryTask = Task {
                for await host in transport.discover(timeout: .seconds(60)) {
                    if !discoveredHosts.contains(where: { $0.id == host.id }) {
                        discoveredHosts.append(host)
                    }
                    consumePendingJoinPayloadIfDiscovered()
                }
            }
        }
        .onDisappear {
            discoveryTask?.cancel()
        }
        // Doc utilisateur — remontée : scanner un code depuis l'écran de découverte, une fois
        // déjà ouvert, ne faisait rien. La boucle ci-dessus ne vérifie `pendingJoinPayload` que
        // pour les hôtes découverts *après* — si le nôtre était déjà dans `discoveredHosts` au
        // moment du scan (cas courant, la découverte tourne dès l'ouverture de l'écran), rien ne
        // le revérifiait jamais.
        .onChange(of: pendingJoinPayload) { _, _ in
            consumePendingJoinPayloadIfDiscovered()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                beginBLEHandoverIfNeeded()
            }
        }
        // Doc utilisateur — remontée : le lien peut retomber plusieurs fois de suite pendant un
        // même passage en arrière-plan (une seule tentative au moment de backgrounder ne suffit
        // pas) — sans ça, il fallait rouvrir l'app et taper « Se reconnecter » à chaque fois.
        .onChange(of: sharedModel?.isHostConnected) { _, isConnected in
            if isConnected == false {
                beginBLEHandoverIfNeeded()
            }
        }
        .sheet(item: $hostAwaitingCode) { host in
            pairingSheet(for: host)
        }
        .fullScreenCover(isPresented: $isPresentingScanner) {
            scannerCover
        }
        // Un balayage vers le bas contournerait `sharedModel?.stop()` : la connexion (Wi-Fi ou,
        // plus tard, BLE) resterait ouverte sans que l'hôte ne le voie jamais — même bug de pair
        // fantôme que celui déjà corrigé pour un vrai tap sur « Quitter ». Seul le bouton de la
        // barre de navigation peut fermer cet écran.
        .interactiveDismissDisabled(true)
    }

    private var discoveryList: some View {
        List {
            Section {
                Button {
                    isPresentingScanner = true
                } label: {
                    Label("Scanner un code", systemImage: "qrcode.viewfinder")
                }
            }

            if !wifiAvailability.isAvailable {
                // Doc 09 — mieux vaut le dire clairement que laisser chercher indéfiniment dans
                // le vide : la découverte initiale reste Wi-Fi uniquement (mDNS/DNS-SD) — le
                // Bluetooth n'intervient qu'en reprise d'une connexion déjà établie
                // (`reconnect()`, `beginBLEHandoverIfNeeded()`), pas pour trouver un hôte la
                // toute première fois.
                EmptyState(
                    icon: "wifi.slash",
                    message: "Le Wi-Fi semble désactivé. Active-le sur cet appareil et sur celui qui partage la partie pour la retrouver."
                )
                .listRowSeparator(.hidden)
            } else if discoveredHosts.isEmpty {
                EmptyState(icon: "wifi", message: "Recherche d'une partie sur le réseau Wi-Fi local…")
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(discoveredHosts) { host in
                        Button {
                            pairingCode = ""
                            isCodePrefilled = false
                            connectionError = nil
                            selectedRole = .observer
                            hostAwaitingCode = host
                        } label: {
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                Text(host.deviceName).font(.h6).foregroundStyle(.textPrimary)
                                Text("\(host.gameID) · \(host.participantCount) joueurs")
                                    .font(.bodySmall)
                                    .foregroundStyle(.textSecondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func consumePendingJoinPayloadIfDiscovered() {
        guard let pending = pendingJoinPayload, let host = discoveredHosts.first(where: { $0.id == pending.matchID }) else { return }
        pendingJoinPayload = nil
        pairingCode = pending.pairingCode
        isCodePrefilled = true
        connectionError = nil
        selectedRole = .observer
        hostAwaitingCode = host
    }

    private var scannerCover: some View {
        ZStack(alignment: .topTrailing) {
            QRScannerView { code in
                isPresentingScanner = false
                guard let url = URL(string: code), let payload = JoinLink.parse(url) else { return }
                pendingJoinPayload = payload
            }
            .ignoresSafeArea()

            Button {
                isPresentingScanner = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .padding()
        }
    }

    private func pairingSheet(for host: DiscoveredHost) -> some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(host.gameID) · \(host.participantCount) joueurs")
                        .font(.bodySmall)
                        .foregroundStyle(.textSecondary)
                }
                if !isCodePrefilled {
                    Section("Code d'appairage") {
                        TextField("6 chiffres", text: $pairingCode)
                            .keyboardType(.numberPad)
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                    }
                }
                Section("Rôle") {
                    Picker("Rôle", selection: $selectedRole) {
                        Text("Observateur").tag(Role.observer)
                        Text("Contributeur").tag(Role.contributor)
                    }
                    .pickerStyle(.segmented)
                    Text(
                        selectedRole == .observer
                            ? "Tu vois le tableau des scores en direct, sans pouvoir le modifier."
                            : "Tu peux proposer des manches ; l'hôte les valide avant qu'elles n'apparaissent chez tout le monde."
                    )
                    .font(.bodySmall)
                    .foregroundStyle(.textTertiary)
                }
                if let connectionError {
                    Text(connectionError).font(.label).foregroundStyle(.semanticError)
                }
            }
            .navigationTitle(host.deviceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { hostAwaitingCode = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isConnecting ? "Connexion…" : "Rejoindre") {
                        Task { await connect(to: host) }
                    }
                    .disabled(pairingCode.count != 6 || isConnecting)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func connect(to host: DiscoveredHost) async {
        guard !isAttemptingConnection else { return }
        isAttemptingConnection = true
        isConnecting = true
        connectionError = nil
        defer {
            isConnecting = false
            isAttemptingConnection = false
        }
        do {
            try await establishConnection(via: transport, to: host)
            hostAwaitingCode = nil
        } catch {
            connectionError = Self.describe(error)
        }
    }

    /// Doc utilisateur — reprise après une connexion perdue (app en arrière-plan, coupure
    /// réseau…). Wi-Fi d'abord (le chemin habituel), Bluetooth ensuite si l'hôte reste
    /// introuvable — orchestration documentée depuis la doc 09/ADR-0014, jamais écrite jusqu'ici.
    /// Relance une découverte courte ciblée sur le même id de partie plutôt que de réutiliser
    /// `DiscoveredHost` tel quel (l'enregistrement peut avoir expiré depuis) ; le code et le rôle
    /// demandé sont encore là, `SharedMatchView` a juste besoin d'un nouveau `SharedMatchModel`
    /// une fois la connexion rétablie.
    private func reconnect() async {
        guard !isAttemptingConnection, let matchID = connectedMatchID else { return }
        isAttemptingConnection = true
        defer { isAttemptingConnection = false }
        if let host = await discoverHost(via: transport, matchID: matchID, timeout: .seconds(8)) {
            if (try? await establishConnection(via: transport, to: host)) != nil { return }
        }
        if let host = await discoverHost(via: bleTransport, matchID: matchID, timeout: .seconds(10)) {
            try? await establishConnection(via: bleTransport, to: host)
        }
    }

    private func discoverHost(via transport: any Transport, matchID: UUID, timeout: Duration) async -> DiscoveredHost? {
        for await host in transport.discover(timeout: timeout) where host.id == matchID {
            return host
        }
        return nil
    }

    private func establishConnection(via transport: any Transport, to host: DiscoveredHost) async throws {
        let transportSession = try await transport.connect(to: host)
        let liveSession = LiveSession(deviceID: DeviceIdentity.current, catalog: catalog)
        try await liveSession.attachToHost(
            transportSession,
            matchID: host.id,
            pairingCode: pairingCode,
            requestedRole: selectedRole,
            deviceName: UIDevice.current.name,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        )
        // Doc utilisateur P9 — l'hôte peut assigner un rôle différent de celui demandé
        // (restriction « observateur uniquement ») : `SharedMatchModel` doit refléter le rôle
        // réel, pas le souhait initial, sinon l'écran propose de saisir des manches qui seront
        // rejetées en silence côté hôte.
        let assignedRole = await liveSession.currentRole()
        // Doc utilisateur — centralisé ici (plutôt que chez chaque appelant) : avec les
        // reconnexions automatiques répétées (`beginBLEHandoverIfNeeded`), laisser une ancienne
        // session sans jamais fermer ses tâches (`SharedMatchModel.tasks`) accumulerait des
        // écouteurs orphelins sur des flux déjà morts à chaque cycle.
        let previousModel = sharedModel
        sharedModel = SharedMatchModel(session: liveSession, role: assignedRole, catalog: catalog)
        connectedMatchID = host.id
        await previousModel?.closeConnection()
    }

    /// Doc utilisateur — remontée : au passage en arrière-plan, la connexion Wi-Fi meurt (pas
    /// d'entitlement réseau en tâche de fond) et l'écran verrouillé du pair se fige sans le dire.
    /// Le Bluetooth bénéficie d'un vrai mode d'arrière-plan (`bluetooth-central`, Info.plist) : on
    /// bascule dessus dans la fenêtre de grâce que `beginBackgroundTask` obtient avant que l'app ne
    /// soit vraiment suspendue.
    ///
    /// Doc utilisateur — remontée (recette physique) : une seule tentative au moment de
    /// backgrounder ne suffisait pas — le lien BLE peut retomber plusieurs fois de suite pendant
    /// un même passage en arrière-plan, sans que rien ne le retente automatiquement. Boucle tant
    /// que le lien manque, l'app reste en arrière-plan, et que le système ne réclame pas la
    /// fenêtre de grâce (`expirationHandler`, seule vraie limite ici — pas un nombre d'essais
    /// choisi arbitrairement).
    private func beginBLEHandoverIfNeeded() {
        guard sharedModel != nil, let matchID = connectedMatchID, backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "cacompte.ble-handover") {
            handoverRetryTask?.cancel()
            Task { @MainActor in endBackgroundTaskIfNeeded() }
        }
        guard backgroundTaskID != .invalid else { return }
        handoverRetryTask = Task {
            // Doc utilisateur : un aller-retour très bref (notification vérifiée puis retour) ne
            // justifie pas de perturber une connexion qui a de bonnes chances de survivre — seul
            // un passage en arrière-plan qui dure déclenche le basculement.
            try? await Task.sleep(for: .seconds(3))
            while !Task.isCancelled, UIApplication.shared.applicationState == .background, sharedModel?.isHostConnected != true {
                await performBLEHandover(matchID: matchID)
                guard !Task.isCancelled, sharedModel?.isHostConnected != true else { break }
                try? await Task.sleep(for: .seconds(10))
            }
            endBackgroundTaskIfNeeded()
        }
    }

    private func performBLEHandover(matchID: UUID) async {
        guard !isAttemptingConnection else { return }
        isAttemptingConnection = true
        defer { isAttemptingConnection = false }
        guard let host = await discoverHost(via: bleTransport, matchID: matchID, timeout: .seconds(8)) else { return }
        guard !Task.isCancelled else { return }
        // Doc utilisateur : si le basculement échoue (Bluetooth désactivé, hôte hors de
        // portée…), on retombe sur le comportement déjà géré — `isHostConnected` reste à `false`,
        // la boucle appelante retentera après le délai. Rien n'est perdu à essayer.
        try? await establishConnection(via: bleTransport, to: host)
    }

    private func endBackgroundTaskIfNeeded() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    /// Distingue l'échec de connexion (réseau, hôte introuvable) de l'absence de réponse
    /// (code d'appairage erroné le plus souvent) — auparavant un seul message générique
    /// « vérifie le code » s'affichait dans les deux cas, ce qui a fait perdre du temps à
    /// diagnostiquer un vrai souci réseau lors de la recette.
    private static func describe(_ error: Error) -> String {
        switch error {
        case WifiTransportError.hostNotFound:
            return "Cet appareil n'est plus joignable sur le réseau. Reviens à la liste et réessaie."
        case LiveSession.SessionError.noResponseFromHost:
            return "L'hôte n'a pas répondu — vérifie le code, et que les deux appareils sont bien sur le même réseau Wi-Fi."
        default:
            return "Connexion impossible (\(error.localizedDescription)). Réessaie."
        }
    }
}
