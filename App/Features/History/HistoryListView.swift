import Catalog
import DesignSystem
import Domain
import Store
import SwiftData
import SwiftUI

struct HistoryListView: View {
    @State private var model: HistoryListModel
    @State private var isPresentingSettings = false
    @State private var editMode: EditMode = .inactive
    @State private var selectedMatchIDs = Set<UUID>()

    init(context: ModelContext, catalog: GameCatalog) {
        _model = State(initialValue: HistoryListModel(context: context, catalog: catalog))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !model.matches.isEmpty, !model.availableGames.isEmpty || !model.availablePlayers.isEmpty {
                    filterBar
                        .padding(.horizontal, Space.lg)
                        .padding(.vertical, Space.sm)
                }
                if model.matches.isEmpty {
                    EmptyState(
                        icon: "clock.arrow.circlepath",
                        message: "Aucune partie terminée pour l'instant. L'historique se remplit à la fin de la première partie."
                    )
                } else {
                    List(selection: $selectedMatchIDs) {
                        Section {
                            if model.filteredMatches.isEmpty {
                                Text("Aucune partie ne correspond à ces filtres.")
                                    .font(.bodyText)
                                    .foregroundStyle(.textSecondary)
                            } else {
                                ForEach(model.filteredMatches) { match in
                                    matchRow(match)
                                        .swipeActions {
                                            Button("Archiver", role: .destructive) {
                                                model.archive(match)
                                            }
                                        }
                                }
                            }
                        }

                        // Doc 01 : mêmes usages qu'`ArchivedPlayersView` — un cas occasionnel,
                        // pas une section à garder visible en permanence dans l'Historique.
                        if model.archivedCount > 0, !editMode.isEditing {
                            Section {
                                NavigationLink {
                                    ArchivedMatchesView(catalog: model.catalog)
                                } label: {
                                    Label("Parties archivées (\(model.archivedCount))", systemImage: "archivebox")
                                        .foregroundStyle(.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Historique")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if editMode.isEditing {
                        Button("Archiver (\(selectedMatchIDs.count))", systemImage: "archivebox", role: .destructive) {
                            archiveSelected()
                        }
                        .tint(.semanticError)
                        .disabled(selectedMatchIDs.isEmpty)
                    } else {
                        Button("Réglages", systemImage: "gearshape") {
                            isPresentingSettings = true
                        }
                    }
                }
                if !model.matches.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        EditButton()
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .sheet(isPresented: $isPresentingSettings) {
                SettingsView()
            }
            .onAppear { model.reload() }
        }
    }

    @Environment(\.modelContext) private var modelContext

    /// En mode édition, `List(selection:)` a besoin d'un contenu de ligne simple — un
    /// `NavigationLink` intercepterait le tap avant la coche de sélection multiple.
    @ViewBuilder
    private func matchRow(_ match: MatchRecord) -> some View {
        if editMode.isEditing {
            row(for: match)
        } else {
            NavigationLink {
                HistoryDetailView(match: match, context: modelContext, catalog: model.catalog)
            } label: {
                row(for: match)
            }
            .buttonStyle(.plain)
        }
    }

    private func archiveSelected() {
        model.archiveMatches(withIDs: selectedMatchIDs)
        selectedMatchIDs.removeAll()
        editMode = .inactive
    }

    private var filterBar: some View {
        HStack(spacing: Space.sm) {
            if !model.availableGames.isEmpty {
                Menu {
                    Button("Tous les jeux") { model.selectedGameID = nil }
                    ForEach(model.availableGames, id: \.id) { game in
                        Button(game.name) { model.selectedGameID = game.id }
                    }
                } label: {
                    filterLabel(
                        model.availableGames.first { $0.id == model.selectedGameID }?.name ?? "Tous les jeux"
                    )
                }
            }
            if !model.availablePlayers.isEmpty {
                Menu {
                    Button("Tous les joueurs") { model.selectedPlayerID = nil }
                    ForEach(model.availablePlayers, id: \.id) { player in
                        Button(player.name) { model.selectedPlayerID = player.id }
                    }
                } label: {
                    filterLabel(
                        model.availablePlayers.first { $0.id == model.selectedPlayerID }?.name ?? "Tous les joueurs"
                    )
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func filterLabel(_ text: String) -> some View {
        Label(text, systemImage: "line.3.horizontal.decrease.circle")
            .font(.label)
            .foregroundStyle(.textPrimary)
            .padding(.horizontal, Space.sm)
            .frame(height: 32)
            .background(.neutralFill, in: .rect(cornerRadius: Radius.sm))
    }

    private func row(for match: MatchRecord) -> some View {
        HStack(spacing: Space.md) {
            Image(systemName: model.gameSymbol(for: match))
                .font(.system(size: IconSize.md))
                .foregroundStyle(.brandInk)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(model.gameName(for: match)).font(.h6).foregroundStyle(.textPrimary)
                Text(match.startedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.bodySmall)
                    .foregroundStyle(.textSecondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: Space.xxs) {
                participantAvatars(for: match)
                if let winner = model.winner(for: match) {
                    Text(winner.nicknameSnapshot).font(.bodySmall).foregroundStyle(.textSecondary)
                }
            }
        }
        .padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Doc utilisateur — tous les participants, pas seulement le vainqueur : empilés avec un
    /// léger recouvrement (motif « pile d'avatars » classique) pour rester compact même à 8
    /// joueurs, plutôt que de s'étaler sur toute la largeur de la ligne.
    private func participantAvatars(for match: MatchRecord) -> some View {
        HStack(spacing: -10) {
            ForEach(match.participants.sorted { $0.seatIndex < $1.seatIndex }, id: \.id) { participant in
                AvatarView(avatar: participant.avatar, size: .small)
                    .overlay(Circle().strokeBorder(.neutralSurface, lineWidth: 2))
            }
        }
    }
}
