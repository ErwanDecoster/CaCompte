import Foundation
import Testing
import SwiftData
@testable import Store

/// Régression : une relation sans inverse déclarée passe silencieusement en local, mais fait
/// planter l'ouverture du `ModelContainer` dès que CloudKit est activé (doc 03, contrainte
/// n°3 : « une relation sans inverse ne synchronise pas »). La validation de forme du schéma
/// (inverses, valeurs par défaut, règles de suppression) a lieu à l'initialisation, avant tout
/// accès réseau — ce test n'a donc pas besoin d'un vrai compte iCloud pour être significatif.
@MainActor
@Suite("Schéma compatible CloudKit")
struct CloudKitSchemaTests {
    @Test("Le schéma s'ouvre sans erreur avec un container CloudKit actif")
    func containerOpensWithCloudKitEnabled() throws {
        let schema = Schema(CaCompteSchemaV1.models)
        let url = FileManager.default.temporaryDirectory.appending(path: "CloudKitSchemaTests-\(UUID()).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .private("iCloud.test.cacompte"))
        _ = try ModelContainer(for: schema, configurations: [config])
    }
}
