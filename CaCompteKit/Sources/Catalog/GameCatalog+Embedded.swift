import Domain
import Foundation

public extension GameCatalog {
    /// Décodées **au lancement** depuis les JSON embarqués (doc 04) — jamais téléchargées.
    /// Un JSON malformé ou un moteur absent de la table doit se voir immédiatement : `try!`
    /// est délibéré, un échec ici est une erreur de build, pas un cas d'exécution normal.
    static let embedded: GameCatalog = {
        let urls = (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "GameDefinitions") ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let decoder = JSONDecoder()
        let definitions = urls.map { url -> GameDefinition in
            let data = try! Data(contentsOf: url)
            return try! decoder.decode(GameDefinition.self, from: data)
        }

        return try! GameCatalog(
            definitions: definitions,
            engineTable: [
                GenericSumRules.engineID: { GenericSumRules() },
                SkyjoRulesV1.engineID: { SkyjoRulesV1() },
                YamsRulesV1.engineID: { YamsRulesV1() },
                BeloteRulesV1.engineID: { BeloteRulesV1() },
                MolkkyRulesV1.engineID: { MolkkyRulesV1() },
            ]
        )
    }()
}
