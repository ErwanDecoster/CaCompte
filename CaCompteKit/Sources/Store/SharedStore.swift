import Foundation

/// Doc utilisateur — Widget (roadmap P9) : l'extension tourne avec son propre identifiant de
/// bundle (`com.cacompte.app.widget`) — sans App Group, elle n'aurait aucun accès au store de
/// l'app. `storeURL` retombe sur `nil` si le groupe n'est pas configuré (entitlement absent,
/// provisionnement en échec) : l'app continue alors sur l'emplacement par défaut de
/// `ModelConfiguration`, seul le widget perd sa source de données — même philosophie de
/// dégradation silencieuse que l'app sans iCloud (doc 03).
public enum SharedStore {
    public static let appGroupIdentifier = "group.com.cacompte.app"

    public static var storeURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appending(path: "CaCompte.sqlite")
    }
}
