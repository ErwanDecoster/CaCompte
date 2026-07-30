import Catalog
import DesignSystem
import Domain
import Store
import SwiftData
import SwiftUI

/// Onglet « Jeux » — point de départ d'une partie (doc 05 : le catalogue s'élargit au fil des
/// phases, cette liste ne fige donc aucun jeu en particulier). `MatchSetupView` reste présentée
/// en feuille : elle porte sa propre `NavigationStack` et ses actions Annuler/Commencer, un
/// `NavigationLink` imbriquerait deux piles de navigation.
struct GamesTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Query(sort: \PlayerRecord.sortIndex) private var allPlayers: [PlayerRecord]
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var currentScrollOffset: CGFloat = 0
    @State private var hasTriggeredSearchFromPull = false
    @State private var selectedDefinition: GameDefinition?
    @State private var activeMatch: MatchRecord?
    @State private var inProgressMatch: MatchRecord?
    @State private var matchPendingAbandon: MatchRecord?
    @State private var isPresentingJoin = false
    @State private var joinPayloadForSheet: JoinLink.Payload?

    /// Distance de glissement du doigt (pas du décalage de contenu) avant d'activer la
    /// recherche. Un tiré volontaire depuis le haut, quand la barre de recherche est déjà
    /// affichée, ne produit aucun décalage de défilement exploitable — le tiroir système de
    /// `.searchable` semble absorber le geste avant qu'il n'atteigne le défilement de la liste.
    /// On suit donc directement le doigt, indépendamment du défilement.
    private static let pullToSearchThreshold: CGFloat = 40

    private var catalog: GameCatalog { .embedded }
    private var activePlayers: [PlayerRecord] { allPlayers.filter { !$0.isArchived } }

    private var games: [GameDefinition] {
        let all = catalog.allGames.sorted { $0.name.fr < $1.name.fr }
        guard !searchText.isEmpty else { return all }
        return all.filter {
            $0.name.fr.localizedCaseInsensitiveContains(searchText)
                || ($0.shortDescription?.fr.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Doc 01 : reprendre une partie en cours reste possible, mais en simple
                // suggestion — un onglet qu'on revisite pour parcourir le catalogue ne doit pas
                // y être redirigé de force à chaque fois.
                if let inProgressMatch {
                    Section {
                        Button {
                            activeMatch = inProgressMatch
                            self.inProgressMatch = nil
                        } label: {
                            resumeRow(for: inProgressMatch)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Abandonner", role: .destructive) {
                                matchPendingAbandon = inProgressMatch
                            }
                        }
                    }
                }

                if !games.isEmpty {
                    Section {
                        ForEach(games) { definition in
                            Button {
                                selectedDefinition = definition
                            } label: {
                                row(for: definition)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if inProgressMatch == nil {
                    EmptyState(icon: "magnifyingglass", message: "Aucun jeu ne correspond à ta recherche.")
                        .listRowSeparator(.hidden)
                }
            }
            .navigationTitle("Jeux")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingJoin = true
                    } label: {
                        Label("Rejoindre une partie", systemImage: "wifi")
                    }
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Rechercher un jeu"
            )
            .searchFocused($isSearchFocused)
            // Doc utilisateur : reproduire le geste de l'écran d'accueil (tiré vers le bas ->
            // recherche activée). `.onScrollGeometryChange` sert uniquement à savoir si on est
            // déjà en haut de la liste — le déclenchement lui-même suit le doigt directement via
            // `simultaneousGesture` ci-dessous, pas le décalage de défilement (qui n'évolue pas
            // de façon exploitable quand on tire depuis le repos avec la barre déjà visible).
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, offsetY in
                currentScrollOffset = offsetY
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        guard currentScrollOffset <= 5, !hasTriggeredSearchFromPull else { return }
                        if value.translation.height > Self.pullToSearchThreshold {
                            hasTriggeredSearchFromPull = true
                            isSearchFocused = true
                        }
                    }
                    .onEnded { _ in
                        hasTriggeredSearchFromPull = false
                    }
            )
            .sheet(item: $selectedDefinition) { definition in
                MatchSetupView(definition: definition, availablePlayers: activePlayers, context: modelContext) { match in
                    selectedDefinition = nil
                    activeMatch = match
                }
            }
            .sheet(isPresented: $isPresentingJoin) {
                JoinMatchView(catalog: catalog, initialPayload: joinPayloadForSheet)
            }
            // Doc utilisateur — un lien `cacompte://` ouvert depuis l'appareil photo système
            // arrive ici, potentiellement alors qu'on est sur un autre onglet ou déjà dans un
            // autre écran ; `DeepLinkRouter` fait le pont depuis `.onOpenURL` (CaCompteApp).
            // `CaCompteApp.selectedTab` garantit que cet onglet est déjà construit quand l'un de
            // ces quatre événements arrive — reste à le consommer, ici et dans `.onAppear`
            // ci-dessous pour le cas où il était déjà en attente au moment du montage (remontée
            // utilisateur : le scan d'un QR code app fermée n'ouvrait rien de visible).
            .onChange(of: deepLinkRouter.pendingJoin) { _, _ in consumePendingDeepLinks() }
            .onChange(of: deepLinkRouter.pendingContinuedMatchID) { _, _ in consumePendingDeepLinks() }
            .onChange(of: deepLinkRouter.pendingGameID) { _, _ in consumePendingDeepLinks() }
            .onChange(of: deepLinkRouter.wantsResume) { _, _ in consumePendingDeepLinks() }
            .navigationDestination(item: $activeMatch) { match in
                MatchPlayView(match: match, context: modelContext, catalog: catalog)
            }
            .onAppear {
                refreshInProgressMatch()
                consumePendingDeepLinks()
            }
            .onChange(of: activeMatch) { oldValue, newValue in
                // La partie ouverte via la bannière peut s'être terminée entre-temps : on
                // rafraîchit dès le retour à la liste plutôt que de garder une référence figée
                // (sinon la bannière reste affichée indéfiniment après une partie terminée).
                if newValue == nil, oldValue != nil {
                    refreshInProgressMatch()
                }
            }
            .confirmationDialog(
                "Abandonner cette partie ?",
                isPresented: Binding(get: { matchPendingAbandon != nil }, set: { if !$0 { matchPendingAbandon = nil } }),
                titleVisibility: .visible
            ) {
                Button("Abandonner", role: .destructive) {
                    if let match = matchPendingAbandon {
                        _ = try? MatchRepository(context: modelContext).abandonMatch(match, catalog: catalog)
                    }
                    matchPendingAbandon = nil
                    refreshInProgressMatch()
                }
            } message: {
                Text("La partie sera classée comme abandonnée dans l'historique, avec le classement atteint jusque-là. Cette action ne peut pas être annulée.")
            }
        }
    }

    /// Doc utilisateur — un seul point qui vérifie les quatre déclencheurs possibles
    /// (`DeepLinkRouter`) et agit sur ceux effectivement en attente ; appelé aussi bien depuis
    /// chaque `.onChange` (nouvel événement pendant que cet onglet est déjà affiché) que depuis
    /// `.onAppear` (événement déjà arrivé avant que cet onglet n'existe).
    private func consumePendingDeepLinks() {
        if let payload = deepLinkRouter.pendingJoin {
            joinPayloadForSheet = payload
            deepLinkRouter.pendingJoin = nil
            isPresentingJoin = true
        }
        if let matchID = deepLinkRouter.pendingContinuedMatchID {
            deepLinkRouter.pendingContinuedMatchID = nil
            activeMatch = try? MatchRepository(context: modelContext).match(withID: matchID)
        }
        if let gameID = deepLinkRouter.pendingGameID {
            deepLinkRouter.pendingGameID = nil
            selectedDefinition = catalog.allGames.first { $0.id == gameID }
        }
        if deepLinkRouter.wantsResume {
            deepLinkRouter.wantsResume = false
            refreshInProgressMatch()
            if let inProgressMatch {
                activeMatch = inProgressMatch
                self.inProgressMatch = nil
            }
        }
    }

    private func refreshInProgressMatch() {
        let repository = MatchRepository(context: modelContext)
        inProgressMatch = try? repository.inProgressMatches().first
    }

    private func resumeRow(for match: MatchRecord) -> some View {
        HStack(spacing: Space.md) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: IconSize.lg))
                .foregroundStyle(.brandBrass)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Reprendre la partie en cours").font(.h6).foregroundStyle(.textPrimary)
                Text(gameName(for: match)).font(.bodySmall).foregroundStyle(.textSecondary)
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

    private func row(for definition: GameDefinition) -> some View {
        HStack(spacing: Space.md) {
            Image(systemName: definition.symbol)
                .font(.system(size: IconSize.lg))
                .foregroundStyle(.brandInk)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(definition.name.fr).font(.h6).foregroundStyle(.textPrimary)
                if let description = definition.shortDescription?.fr {
                    Text(description).font(.bodySmall).foregroundStyle(.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
