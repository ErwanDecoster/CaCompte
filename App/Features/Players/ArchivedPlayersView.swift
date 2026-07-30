import DesignSystem
import Store
import SwiftData
import SwiftUI

/// Écran séparé plutôt qu'une section toujours visible dans `PlayersListView` — les joueurs
/// archivés sont un cas d'usage occasionnel (retrouver quelqu'un pour le réactiver), pas
/// quelque chose à afficher en permanence à côté du répertoire actif.
struct ArchivedPlayersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlayerRecord.sortIndex) private var allPlayers: [PlayerRecord]
    @State private var playerPendingDeletion: PlayerRecord?

    private var archivedPlayers: [PlayerRecord] { allPlayers.filter { $0.isArchived } }

    var body: some View {
        List {
            if archivedPlayers.isEmpty {
                EmptyState(icon: "archivebox", message: "Aucun joueur archivé.")
                    .listRowSeparator(.hidden)
            } else {
                ForEach(archivedPlayers) { player in
                    HStack {
                        NavigationLink {
                            ProfileView(player: player)
                        } label: {
                            row(for: player)
                        }
                        .buttonStyle(.plain)
                        Button("Réactiver") {
                            try? PlayerRepository(context: modelContext).unarchive(player)
                        }
                        .buttonStyle(.tertiary(size: .small))
                    }
                    .swipeActions {
                        Button("Supprimer", systemImage: "trash", role: .destructive) {
                            playerPendingDeletion = player
                        }
                    }
                }
            }
        }
        .navigationTitle("Joueurs archivés")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Supprimer définitivement ce joueur ?",
            isPresented: Binding(get: { playerPendingDeletion != nil }, set: { if !$0 { playerPendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let player = playerPendingDeletion {
                    try? PlayerRepository(context: modelContext).delete(player)
                }
                playerPendingDeletion = nil
            }
        } message: {
            Text("La fiche joueur sera définitivement supprimée. Les parties déjà jouées restent dans l'historique, mais ne pointeront plus vers ce joueur. Cette action ne peut pas être annulée.")
        }
    }

    private func row(for player: PlayerRecord) -> some View {
        HStack(spacing: Space.md) {
            AvatarView(avatar: player.avatar, size: .medium)
            Text(player.nickname)
                .font(.bodyText)
                .foregroundStyle(.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
