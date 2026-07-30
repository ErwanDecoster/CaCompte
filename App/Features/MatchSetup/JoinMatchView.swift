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
    @State private var transport = WifiTransport(deviceName: UIDevice.current.name)
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
                    SharedMatchView(model: sharedModel)
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
                    if let pending = pendingJoinPayload, pending.matchID == host.id {
                        pendingJoinPayload = nil
                        pairingCode = pending.pairingCode
                        isCodePrefilled = true
                        connectionError = nil
                        selectedRole = .observer
                        hostAwaitingCode = host
                    }
                }
            }
        }
        .onDisappear {
            discoveryTask?.cancel()
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
                // le vide : sans Wi-Fi, aucun hôte ne peut être découvert (pas de secours
                // Bluetooth branché dans l'app pour l'instant).
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
        isConnecting = true
        connectionError = nil
        do {
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
            sharedModel = SharedMatchModel(session: liveSession, role: selectedRole, catalog: catalog)
            hostAwaitingCode = nil
        } catch {
            connectionError = Self.describe(error)
        }
        isConnecting = false
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
