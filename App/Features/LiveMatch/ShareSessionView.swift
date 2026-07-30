import DesignSystem
import Sync
import SwiftUI
import UIKit

/// Doc 09 — l'hôte annonce la partie, affiche le code d'appairage et la liste des appareils
/// connectés. Fermer cette feuille n'arrête pas le partage : c'est une fenêtre sur une session
/// qui continue en arrière-plan, jusqu'à « Arrêter le partage » explicite (doc 09 « Dégradation »
/// — le partage est un supplément, jamais un prérequis pour continuer à jouer).
struct ShareSessionView: View {
    let model: LiveMatchModel
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var isStopping = false
    @State private var wifiAvailability = WiFiAvailability()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Partager la partie")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") { dismiss() }
                    }
                }
                .task {
                    guard !model.isSharing else { return }
                    await startSharing()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let code = model.pairingCode {
            List {
                if !wifiAvailability.isAvailable {
                    Section {
                        Text("Le Wi-Fi semble désactivé : personne ne pourra te rejoindre tant qu'il ne l'est pas.")
                            .font(.label)
                            .foregroundStyle(.semanticError)
                    }
                }

                Section {
                    VStack(spacing: Space.sm) {
                        if let joinURL = JoinLink.url(matchID: model.state.matchID, pairingCode: code) {
                            QRCodeView(url: joinURL)
                                .frame(width: 180, height: 180)
                                .padding(.bottom, Space.xs)
                        }
                        Text("Code d'appairage")
                            .font(.label)
                            .foregroundStyle(.textSecondary)
                        Text(code)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .tracking(4)
                        Text("À scanner (bouton « Scanner un code » sur l'appareil qui rejoint) ou à saisir, sur le même Wi-Fi.")
                            .font(.bodySmall)
                            .foregroundStyle(.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.lg)
                }

                Section("Appareils connectés") {
                    if model.connectedPeers.isEmpty {
                        Text("En attente d'un appareil qui rejoint…")
                            .foregroundStyle(.textTertiary)
                    } else {
                        ForEach(model.connectedPeers) { peer in
                            HStack {
                                Text(peer.deviceName)
                                    .foregroundStyle(.textPrimary)
                                Spacer()
                                Text(roleLabel(peer.role))
                                    .font(.label)
                                    .foregroundStyle(.textSecondary)
                            }
                        }
                    }
                }

                Section {
                    Button("Arrêter le partage", role: .destructive) {
                        Task {
                            isStopping = true
                            await model.stopSharing()
                            isStopping = false
                            dismiss()
                        }
                    }
                    .disabled(isStopping)
                }
            }
        } else if errorMessage != nil {
            EmptyState(
                icon: "wifi.exclamationmark",
                message: "Impossible de démarrer le partage. Vérifie que le Wi-Fi est activé et réessaie.",
                actionTitle: "Réessayer"
            ) {
                Task { await startSharing() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView("Démarrage du partage…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func startSharing() async {
        errorMessage = nil
        do {
            try await model.startSharing(deviceName: UIDevice.current.name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func roleLabel(_ role: Role) -> LocalizedStringResource {
        switch role {
        case .host: "Hôte"
        case .contributor: "Contributeur"
        case .observer: "Observateur"
        }
    }
}
