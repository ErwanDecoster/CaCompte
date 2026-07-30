/// Doc 04 « Catalogue et chargement ». Le contenu (définitions + table des moteurs) est fourni
/// par l'appelant — `Domain` ne connaît aucune implémentation concrète de `GameRules` ; c'est
/// `Catalog` qui assemble `GameCatalog.embedded` avec ses JSON et ses moteurs.
public struct GameCatalog: Sendable {
    private let definitionsByID: [String: GameDefinition]
    private let engineTable: [String: @Sendable () -> any GameRules]

    /// Échoue si un JSON référence un moteur absent de `engineTable` — l'exhaustivité voulue
    /// par doc 04 est ainsi vérifiée à la construction, pas découverte au runtime.
    public init(definitions: [GameDefinition], engineTable: [String: @Sendable () -> any GameRules]) throws {
        for definition in definitions where engineTable[definition.engine] == nil {
            throw GameCatalogError.unknownEngine(definition.engine)
        }
        self.definitionsByID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        self.engineTable = engineTable
    }

    public func definition(for gameID: String, version: Int) throws -> GameDefinition {
        guard let definition = definitionsByID[gameID], definition.rulesVersion == version else {
            throw GameCatalogError.unknownGame(gameID: gameID, version: version)
        }
        return definition
    }

    public func rules(for gameID: String, version: Int) throws -> any GameRules {
        let definition = try definition(for: gameID, version: version)
        guard let factory = engineTable[definition.engine] else {
            throw GameCatalogError.unknownEngine(definition.engine)
        }
        return factory()
    }

    public var allGames: [GameDefinition] {
        Array(definitionsByID.values)
    }
}

public enum GameCatalogError: Error, Sendable, Equatable {
    case unknownGame(gameID: String, version: Int)
    case unknownEngine(String)
}
