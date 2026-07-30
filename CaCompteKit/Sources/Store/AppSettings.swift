import Foundation
import Observation

/// Doc 03 « AppSettings ». Le consentement iCloud ne peut pas vivre *dans* le container
/// CloudKit qu'il conditionne (poule et l'œuf : le container n'existe pas encore quand on le
/// lit) — et le synchroniser via iCloud serait de toute façon contradictoire avec un réglage
/// pensé par appareil. Stocké en `UserDefaults`, en dehors du schéma SwiftData.
@Observable
public final class AppSettings {
    /// Doc 01 : tri automatique (habitués d'abord, par nombre de parties jouées) par défaut ;
    /// le tri manuel (glisser-déposer) reste disponible pour qui préfère composer sa propre
    /// liste.
    public enum PlayerSortMode: String, Sendable, CaseIterable {
        case automatic
        case manual
    }

    private let defaults: UserDefaults
    private static let iCloudSyncEnabledKey = "iCloudSyncEnabled"
    private static let playerSortModeKey = "playerSortMode"

    public var iCloudSyncEnabled: Bool {
        didSet { defaults.set(iCloudSyncEnabled, forKey: Self.iCloudSyncEnabledKey) }
    }

    public var playerSortMode: PlayerSortMode {
        didSet { defaults.set(playerSortMode.rawValue, forKey: Self.playerSortModeKey) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.iCloudSyncEnabled = defaults.object(forKey: Self.iCloudSyncEnabledKey) as? Bool ?? true
        self.playerSortMode = defaults.string(forKey: Self.playerSortModeKey).flatMap(PlayerSortMode.init(rawValue:)) ?? .automatic
    }
}
