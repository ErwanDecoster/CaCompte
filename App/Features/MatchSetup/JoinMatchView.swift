import Catalog
import DesignSystem
import Domain
import Store
import Sync
import SwiftUI
import UIKit

/// Doc 09, révisé P9 — écran « Rejoindre une partie ». Remplace l'ancienne découverte Wi-Fi (une
/// liste d'hôtes trouvés sur le réseau local) par une simple saisie du code d'appairage : Supabase
/// Realtime (`MatchConnectionCoordinator`/`SupabaseTransport`) résout directement le code vers la
/// partie correspondante, sans aucune notion de proximité réseau/Bluetooth — voir l'historique Git
/// pour la suite de correctifs Wi-Fi/BLE que ça remplace.
///
/// `MatchConnectionCoordinator.shared` porte la connexion pour toute la durée de l'app plutôt que
/// pour la durée de cet écran — nécessaire pour survivre à la fermeture de cet écran ou à un
/// relancement du process (voir sa doc).
struct JoinMatchView: View {
    let catalog: GameCatalog

    @Environment(\.dismiss) private var dismiss
    private var coordinator: MatchConnectionCoordinator { .shared }
    @State private var pairingCode = ""
    @State private var selectedRole: Role = .observer
    @State private var isConnecting = false
    @State private var connectionError: String?
    @State private var isPresentingScanner = false

    init(catalog: GameCatalog, initialPayload: JoinLink.Payload? = nil) {
        self.catalog = catalog
        if let initialPayload {
            _pairingCode = State(initialValue: initialPayload.pairingCode)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let sharedModel = coordinator.sharedModel {
                    SharedMatchView(model: sharedModel, onReconnect: reconnect)
                } else {
                    joinForm
                }
            }
            .navigationTitle("Rejoindre une partie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(coordinator.sharedModel == nil ? "Fermer" : "Quitter") {
                        Task {
                            await coordinator.stop()
                            dismiss()
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $isPresentingScanner) {
            scannerCover
        }
        // Un balayage vers le bas contournerait `coordinator.stop()` : la connexion resterait
        // ouverte sans que l'hôte ne le voie jamais — même bug de pair fantôme que celui déjà
        // corrigé pour un vrai tap sur « Quitter ». Seul le bouton de la barre de navigation peut
        // fermer cet écran (fermer cet écran ne quitte d'ailleurs plus la partie du tout — voir
        // doc sur `coordinator` : la reconnexion continue même une fois cet écran fermé).
        .interactiveDismissDisabled(true)
    }

    private var joinForm: some View {
        Form {
            Section {
                Button {
                    isPresentingScanner = true
                } label: {
                    Label("Scanner un code", systemImage: "qrcode.viewfinder")
                }
            }
            Section("Code d'appairage") {
                TextField("6 chiffres", text: $pairingCode)
                    .keyboardType(.numberPad)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .onChange(of: pairingCode) { _, newValue in
                        pairingCode = String(newValue.filter(\.isNumber).prefix(6))
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
            Section {
                Button(isConnecting ? "Connexion…" : "Rejoindre") {
                    Task { await connect() }
                }
                .disabled(pairingCode.count != 6 || isConnecting)
            }
        }
    }

    private var scannerCover: some View {
        ZStack(alignment: .topTrailing) {
            QRScannerView { code in
                isPresentingScanner = false
                guard let url = URL(string: code), let payload = JoinLink.parse(url) else { return }
                pairingCode = payload.pairingCode
                Task { await connect() }
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

    private func connect() async {
        isConnecting = true
        connectionError = nil
        defer { isConnecting = false }
        do {
            try await coordinator.join(
                code: pairingCode,
                deviceName: UIDevice.current.name,
                requestedRole: selectedRole,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            )
        } catch {
            connectionError = Self.describe(error)
        }
    }

    /// Doc utilisateur — reprise après une connexion perdue, déclenchée par le bouton
    /// « Se reconnecter » de `SharedMatchView`.
    private func reconnect() async -> Bool {
        await coordinator.reconnectNow()
    }

    /// Distingue l'échec de connexion (code introuvable) de l'absence de réponse (code trouvé
    /// mais mauvais code de chiffrement, ou hôte muet) — deux causes différentes, deux messages.
    private static func describe(_ error: Error) -> String {
        switch error {
        case SupabaseTransportError.gameNotFound:
            return "Aucune partie ne correspond à ce code. Vérifie qu'il est bien à jour."
        case LiveSession.SessionError.noResponseFromHost:
            return "L'hôte n'a pas répondu — vérifie le code."
        default:
            return "Connexion impossible (\(error.localizedDescription)). Réessaie."
        }
    }
}
