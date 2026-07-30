import Catalog
import Domain
import Store
import SwiftData
import SwiftUI

@main
struct CaCompteApp: App {
    private let settings = AppSettings()
    private let deepLinkRouter = DeepLinkRouter()
    @State private var container: ModelContainer?

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    TabView {
                        PlayersListView()
                            .tabItem { Label("Joueurs", systemImage: "person.2.fill") }
                        GamesTabView()
                            .tabItem { Label("Jeux", systemImage: "die.face.5.fill") }
                        HistoryListView(context: container.mainContext, catalog: .embedded)
                            .tabItem { Label("Historique", systemImage: "clock.arrow.circlepath") }
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
                guard let payload = JoinLink.parse(url) else { return }
                deepLinkRouter.pendingJoin = payload
            }
            // Doc utilisateur « Handoff » (P9) — reprise sur un autre appareil connecté au même
            // compte iCloud : même pont que `.onOpenURL` ci-dessus, jusqu'à `GamesTabView`.
            .onContinueUserActivity(MatchContinuation.activityType) { activity in
                guard let matchID = MatchContinuation.matchID(from: activity) else { return }
                deepLinkRouter.pendingContinuedMatchID = matchID
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
    private static func loadContainer(iCloudSyncEnabled: Bool) async -> ModelContainer {
        await Task.detached(priority: .userInitiated) {
            let schema = Schema(CaCompteSchemaV1.models)
            if iCloudSyncEnabled,
               let cloudContainer = try? ModelContainer(
                   for: schema,
                   migrationPlan: CaCompteMigrationPlan.self,
                   configurations: [ModelConfiguration(schema: schema, cloudKitDatabase: .private("iCloud.com.cacompte.app"))]
               ) {
                return cloudContainer
            }
            return try! ModelContainer(
                for: schema,
                migrationPlan: CaCompteMigrationPlan.self,
                configurations: [ModelConfiguration(schema: schema, cloudKitDatabase: .none)]
            )
        }.value
    }
}
