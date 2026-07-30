import Domain

/// Doc 04 : « un jeu simple n'implémente rien du tout. » Les quatre méthodes viennent
/// entièrement de l'extension par défaut de `GameRules`. Sert tous les jeux dont
/// `"engine": "generic.sum.v1"`.
public struct GenericSumRules: GameRules {
    public static let engineID = "generic.sum.v1"

    public init() {}
}
