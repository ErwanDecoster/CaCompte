import Catalog
import Domain
import Store
import SwiftData
import SwiftUI
import WidgetKit

/// Doc utilisateur — onglets adressables par un deep link (`CaCompteApp.selectedTab`) : sans ça,
/// un lien `cacompte://`/Handoff/App Intent qui arrive alors que « Jeux » n'est pas l'onglet actif
/// pouvait rester sans effet visible — `TabView` ne construit un onglet non sélectionné qu'à la
/// demande, `GamesTabView` n'existait donc pas encore pour recevoir l'événement (remontée
/// utilisateur : « le scan du QR code ouvre bien l'application mais rien ne se passe »).
private enum AppTab: Hashable {
    case players, games, history
}

@main
struct CaCompteApp: App {
    private let settings = AppSettings()
    private let deepLinkRouter = DeepLinkRouter.shared
    @State private var container: ModelContainer?
    @State private var selectedTab: AppTab = .players
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    TabView(selection: $selectedTab) {
                        PlayersListView()
                            .tabItem { Label("Joueurs", systemImage: "person.2.fill") }
                            .tag(AppTab.players)
                        GamesTabView()
                            .tabItem { Label("Jeux", systemImage: "die.face.5.fill") }
                            .tag(AppTab.games)
                        HistoryListView(context: container.mainContext, catalog: .embedded)
                            .tabItem { Label("Historique", systemImage: "clock.arrow.circlepath") }
                            .tag(AppTab.history)
                    }
                    .environment(settings)
                    .environment(deepLinkRouter)
                    .modelContainer(container)
                } else {
                    ProgressView()
                        .task {
                            container = await Self.loadContainer(iCloudSyncEnabled: settings.iCloudSyncEnabled)
                        }
                }
            }
            // Doc utilisateur — code d'appairage scanné par l'appareil photo système (schéma
            // `cacompte://`, doc 09) : `DeepLinkRouter` fait le pont jusqu'à `GamesTabView`,
            // potentiellement affichée sur un autre onglet au moment où le lien s'ouvre.
            .onOpenURL { url in
                // Doc utilisateur — Widget (P9) : tap sur la carte de partie en cours
                // (`cacompte://resume`, posé par `MatchWidgetEntryView.widgetURL`).
                if url.host == "resume" {
                    deepLinkRouter.wantsResume = true
                    return
                }
                guard let payload = JoinLink.parse(url) else { return }
                deepLinkRouter.pendingJoin = payload
            }
            // Doc utilisateur — Widget (P9) : un score ne change que sur action explicite d'un
            // joueur (doc `MatchTimelineProvider`), donc pas de rafraîchissement périodique côté
            // widget — c'est l'app qui republie sa timeline, au moment le plus probable où
            // l'utilisateur va la consulter (elle vient de quitter l'app).
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
            // Doc utilisateur « Handoff » (P9) — reprise sur un autre appareil connecté au même
            // compte iCloud : même pont que `.onOpenURL` ci-dessus, jusqu'à `GamesTabView`.
            .onContinueUserActivity(MatchContinuation.activityType) { activity in
                guard let matchID = MatchContinuation.matchID(from: activity) else { return }
                deepLinkRouter.pendingContinuedMatchID = matchID
            }
            // Doc utilisateur — ces quatre déclencheurs (lien, Handoff, App Intents « Commence »/
            // « Reprends ») veulent tous dire la même chose : montrer l'onglet Jeux. Posé ici (le
            // `Group` racine, toujours monté dès le lancement) plutôt que dans `GamesTabView` :
            // c'est justement ce qui manquait pour que l'onglet soit *construit* à temps.
            .onChange(of: deepLinkRouter.pendingJoin) { _, newValue in
                if newValue != nil { selectedTab = .games }
            }
            .onChange(of: deepLinkRouter.pendingContinuedMatchID) { _, newValue in
                if newValue != nil { selectedTab = .games }
            }
            .onChange(of: deepLinkRouter.pendingGameID) { _, newValue in
                if newValue != nil { selectedTab = .games }
            }
            .onChange(of: deepLinkRouter.wantsResume) { _, newValue in
                if newValue { selectedTab = .games }
            }
        }
    }

    /// Doc 03 : la première activation de CloudKit (création des zones, poussée du schéma) peut
    /// prendre plusieurs secondes — hors du thread principal pour ne jamais figer le premier
    /// écran pendant ce temps (un blocage synchrone ici se lisait comme une page blanche
    /// indéfinie, pas comme un chargement). Si CloudKit échoue à s'initialiser (compte
    /// indisponible, container mal provisionné, réseau absent), on retombe sur un stockage
    /// local : « un utilisateur qui refuse iCloud garde une app pleinement fonctionnelle »
    /// s'applique aussi si iCloud est coché mais indisponible.
    /// Doc utilisateur — Widget (P9) : le store vit dans le conteneur App Group quand il est
    /// disponible, pour que l'extension widget (bundle id séparé, doc `SharedStore`) puisse lire
    /// les mêmes données sans dupliquer la synchronisation CloudKit. Retombe sur l'emplacement
    /// par défaut si le groupe n'est pas provisionné — l'app reste utilisable, seul le widget
    /// perd sa source.
    private nonisolated static func configuration(schema: Schema, cloudKitDatabase: ModelConfiguration.CloudKitDatabase) -> ModelConfiguration {
        guard let sharedURL = SharedStore.storeURL else {
            return ModelConfiguration(schema: schema, cloudKitDatabase: cloudKitDatabase)
        }
        return ModelConfiguration(schema: schema, url: sharedURL, cloudKitDatabase: cloudKitDatabase)
    }

    private static func loadContainer(iCloudSyncEnabled: Bool) async -> ModelContainer {
        await Task.detached(priority: .userInitiated) {
            let schema = Schema(CaCompteSchemaV1.models)
            if iCloudSyncEnabled,
               let cloudContainer = try? ModelContainer(
                   for: schema,
                   migrationPlan: CaCompteMigrationPlan.self,
                   configurations: [configuration(schema: schema, cloudKitDatabase: .private("iCloud.com.cacompte.app"))]
               ) {
                return cloudContainer
            }
            return try! ModelContainer(
                for: schema,
                migrationPlan: CaCompteMigrationPlan.self,
                configurations: [configuration(schema: schema, cloudKitDatabase: .none)]
            )
        }.value
    }
}
