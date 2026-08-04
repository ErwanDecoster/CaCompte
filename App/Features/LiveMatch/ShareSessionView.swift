import DesignSystem
import Sync
import SwiftUI

/// Doc 09 — l'hôte annonce la session (une ou plusieurs parties, doc 09 « Fin de partie »),
/// affiche le code d'appairage et la liste des appareils connectés. Fermer cette feuille n'arrête
/// pas le partage : c'est une fenêtre sur une session qui continue en arrière-plan, jusqu'à
/// « Arrêter le partage » explicite (doc 09 « Dégradation » — le partage est un supplément, jamais
/// un prérequis pour continuer à jouer).
///
/// Découplée de `LiveMatchModel` (lit `LiveShareCoordinator.shared` directement) pour rester
/// utilisable même hors d'un écran de partie — depuis `GamesTabView`, entre deux parties d'une
/// même session (doc 09 « Fin de partie »). `startAction` n'est fourni que par `LiveMatchView` :
/// c'est ce qui distingue « ouvrir cet écran pour démarrer un tout nouveau partage » de « ouvrir
/// cet écran pour observer/arrêter une session déjà en cours ».
struct ShareSessionView: View {
    var startAction: ((_ allowsContributors: Bool) async throws -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var isStopping = false
    /// Doc utilisateur P9 — remontée : pouvoir imposer « observateur uniquement » à la création
    /// (ou en cours) du partage. Ne rétrograde pas un contributeur déjà connecté (doc
    /// `LiveSession.setAllowsContributors`), seulement les prochaines connexions.
    @State private var allowsContributors = true
    private var coordinator: LiveShareCoordinator { .shared }

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
                    guard startAction != nil, !coordinator.isSharing else { return }
                    await startSharing()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let code = coordinator.pairingCode {
            List {
                Section {
                    VStack(spacing: Space.sm) {
                        if let joinURL = JoinLink.url(pairingCode: code) {
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
                        Text("À scanner (bouton « Scanner un code » sur l'appareil qui rejoint) ou à saisir — aucune connexion Wi-Fi commune n'est nécessaire, juste une connexion Internet des deux côtés.")
                            .font(.bodySmall)
                            .foregroundStyle(.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.lg)
                }

                Section {
                    Toggle("Autoriser les contributeurs", isOn: $allowsContributors)
                        .tint(.brandInk)
                        .onChange(of: allowsContributors) { _, newValue in
                            Task { await coordinator.setAllowsContributors(newValue) }
                        }
                    Text(
                        allowsContributors
                            ? "Les personnes qui rejoignent peuvent choisir d'observer ou de proposer des manches."
                            : "Les personnes qui rejoignent ne peuvent qu'observer, quel que soit leur choix — ça ne change rien pour les contributeurs déjà connectés."
                    )
                    .font(.bodySmall)
                    .foregroundStyle(.textTertiary)
                }

                Section("Appareils connectés") {
                    if coordinator.connectedPeers.isEmpty {
                        Text("En attente d'un appareil qui rejoint…")
                            .foregroundStyle(.textTertiary)
                    } else {
                        ForEach(coordinator.connectedPeers) { peer in
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
                            await coordinator.stopSharing()
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
                message: "Impossible de démarrer le partage. Vérifie ta connexion Internet et réessaie.",
                actionTitle: "Réessayer"
            ) {
                Task { await startSharing() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if startAction != nil {
            ProgressView("Démarrage du partage…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Doc 09 « Fin de partie » — ouvert depuis `GamesTabView` (`startAction == nil`) alors
            // que la session vient de s'arrêter (ex. tap sur « Arrêter le partage » juste avant que
            // cette feuille ne se ferme) : rien à démarrer depuis ici, seul un état de repli le
            // temps que le bouton qui a ouvert cet écran disparaisse à son tour.
            EmptyState(icon: "wifi.slash", message: "Aucune session partagée en cours.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func startSharing() async {
        guard let startAction else { return }
        errorMessage = nil
        do {
            try await startAction(allowsContributors)
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
