import Catalog
import DesignSystem
import Domain
import Store
import SwiftData
import SwiftUI

/// Écran séparé plutôt qu'une section toujours visible dans `HistoryListView` — les parties
/// archivées sont un cas d'usage occasionnel, même logique que `ArchivedPlayersView`.
struct ArchivedMatchesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MatchRecord.startedAt, order: .reverse) private var allMatches: [MatchRecord]
    let catalog: GameCatalog
    @State private var matchPendingDeletion: MatchRecord?

    private var archivedMatches: [MatchRecord] { allMatches.filter(\.isArchived) }

    var body: some View {
        List {
            if archivedMatches.isEmpty {
                EmptyState(icon: "archivebox", message: "Aucune partie archivée.")
                    .listRowSeparator(.hidden)
            } else {
                ForEach(archivedMatches) { match in
                    HStack {
                        NavigationLink {
                            HistoryDetailView(match: match, context: modelContext, catalog: catalog)
                        } label: {
                            row(for: match)
                        }
                        .buttonStyle(.plain)
                        Button("Réactiver") {
                            try? MatchRepository(context: modelContext).unarchive(match)
                        }
                        .buttonStyle(.tertiary(size: .small))
                    }
                    .swipeActions {
                        Button("Supprimer", systemImage: "trash", role: .destructive) {
                            matchPendingDeletion = match
                        }
                    }
                }
            }
        }
        .navigationTitle("Parties archivées")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Supprimer définitivement cette partie ?",
            isPresented: Binding(get: { matchPendingDeletion != nil }, set: { if !$0 { matchPendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let match = matchPendingDeletion {
                    try? MatchRepository(context: modelContext).delete(match)
                }
                matchPendingDeletion = nil
            }
        } message: {
            Text("La partie et ses manches seront définitivement supprimées, y compris des statistiques des joueurs concernés. Cette action ne peut pas être annulée.")
        }
    }

    private func row(for match: MatchRecord) -> some View {
        HStack(spacing: Space.md) {
            Image(systemName: gameSymbol(for: match))
                .font(.system(size: IconSize.md))
                .foregroundStyle(.brandInk)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(gameName(for: match)).font(.h6).foregroundStyle(.textPrimary)
                Text(match.startedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.bodySmall)
                    .foregroundStyle(.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func gameName(for match: MatchRecord) -> String {
        (try? catalog.definition(for: match.gameID, version: match.rulesVersion))?.name.fr ?? match.gameID
    }

    private func gameSymbol(for match: MatchRecord) -> String {
        (try? catalog.definition(for: match.gameID, version: match.rulesVersion))?.symbol ?? "circle"
    }
}
