import DesignSystem
import Domain
import Store
import SwiftData
import SwiftUI

struct PlayersListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Query(sort: \PlayerRecord.sortIndex) private var allPlayers: [PlayerRecord]
    @State private var isPresentingCreation = false
    @State private var editMode: EditMode = .inactive
    @State private var selectedPlayerIDs = Set<UUID>()

    /// Doc 01 : tri automatique par nombre de parties jouées (habitués d'abord) par défaut,
    /// tri manuel (glisser-déposer) en option — réglable dans Réglages.
    private var activePlayers: [PlayerRecord] {
        let filtered = allPlayers.filter { !$0.isArchived }
        guard settings.playerSortMode == .automatic else { return filtered }
        return filtered.sorted { lhs, rhs in
            let lhsCount = matchesPlayedCount(for: lhs)
            let rhsCount = matchesPlayedCount(for: rhs)
            guard lhsCount == rhsCount else { return lhsCount > rhsCount }
            return lhs.sortIndex < rhs.sortIndex
        }
    }

    private var archivedCount: Int { allPlayers.count { $0.isArchived } }

    private var onMoveAction: ((IndexSet, Int) -> Void)? {
        guard settings.playerSortMode == .manual else { return nil }
        return move
    }

    var body: some View {
        NavigationStack {
            List(selection: $selectedPlayerIDs) {
                Section {
                    if activePlayers.isEmpty {
                        EmptyState(
                            icon: "person.crop.circle.badge.plus",
                            message: "Aucun joueur. Ajouter un joueur",
                            actionTitle: "Ajouter un joueur"
                        ) {
                            isPresentingCreation = true
                        }
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(activePlayers) { player in
                            playerRow(player)
                                .swipeActions {
                                    Button("Archiver", role: .destructive) {
                                        try? PlayerRepository(context: modelContext).archive(player)
                                    }
                                }
                        }
                        .onMove(perform: onMoveAction)
                    }
                }

                // Doc 01 : les joueurs archivés restent accessibles, mais en retrait — une
                // liste toujours visible pour un cas d'usage occasionnel prenait trop de place.
                if archivedCount > 0, !editMode.isEditing {
                    Section {
                        NavigationLink {
                            ArchivedPlayersView()
                        } label: {
                            Label("Joueurs archivés (\(archivedCount))", systemImage: "archivebox")
                                .foregroundStyle(.textSecondary)
                        }
                    }
                }
            }
            .navigationTitle("Joueurs")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if editMode.isEditing {
                        Button("Archiver (\(selectedPlayerIDs.count))", systemImage: "archivebox", role: .destructive) {
                            archiveSelected()
                        }
                        .tint(.semanticError)
                        .disabled(selectedPlayerIDs.isEmpty)
                    } else {
                        Button("Ajouter un joueur", systemImage: "plus") {
                            isPresentingCreation = true
                        }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    EditButton()
                }
            }
            .environment(\.editMode, $editMode)
            .sheet(isPresented: $isPresentingCreation) {
                PlayerEditorView(mode: .create, context: modelContext)
            }
        }
    }

    /// En mode édition, `List(selection:)` a besoin d'un contenu de ligne simple pour proposer
    /// sa coche de sélection multiple — un `NavigationLink` intercepte le tap avant elle.
    @ViewBuilder
    private func playerRow(_ player: PlayerRecord) -> some View {
        if editMode.isEditing {
            row(for: player)
        } else {
            NavigationLink {
                ProfileView(player: player)
            } label: {
                row(for: player)
            }
            .buttonStyle(.plain)
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

    private func matchesPlayedCount(for player: PlayerRecord) -> Int {
        player.participations.filter { $0.match?.statusRaw == MatchStatus.ended.rawValue }.count
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = activePlayers
        reordered.move(fromOffsets: source, toOffset: destination)
        try? PlayerRepository(context: modelContext).reorder(reordered)
    }

    private func archiveSelected() {
        let repository = PlayerRepository(context: modelContext)
        for player in activePlayers where selectedPlayerIDs.contains(player.id) {
            try? repository.archive(player)
        }
        selectedPlayerIDs.removeAll()
        editMode = .inactive
    }
}
