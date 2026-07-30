import Foundation

/// Doc 09 — le `deviceID` qui départage l'horloge de Lamport `(lamport, deviceID)` doit être
/// stable pour un même appareil à travers les sessions. Généré une fois, persisté en
/// `UserDefaults` comme `AppSettings` : suffisant pour départager plusieurs appareils pendant
/// une partie, une réinstallation n'a pas besoin d'en hériter.
public enum DeviceIdentity {
    private static let key = "deviceID"

    public static var current: String {
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }
}
