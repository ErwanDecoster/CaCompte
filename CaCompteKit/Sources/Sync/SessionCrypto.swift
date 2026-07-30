import CryptoKit
import Foundation

/// Doc 09 « Appairage et chiffrement » — remplace le chiffrement gratuit de MultipeerConnectivity,
/// perdu en passant à des sockets/GATT bruts (ADR-0014). `CryptoKit` est un framework système :
/// aucune dépendance tierce ajoutée (ADR-0012).
enum SessionCrypto {
    enum CryptoError: Error, Sendable, Equatable {
        case sealFailed
    }

    /// Affiché en clair par l'hôte (et encodé dans un QR) ; ne transite jamais sur le réseau —
    /// seule la clé qui en dérive y transite, jamais le code lui-même.
    static func generatePairingCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    /// HKDF-SHA256 : le `matchID` sert de sel, ce qui garantit une clé différente par partie même
    /// si deux hôtes choisissent le même code par coïncidence.
    static func deriveKey(pairingCode: String, matchID: UUID) -> SymmetricKey {
        let inputKeyMaterial = SymmetricKey(data: Data(pairingCode.utf8))
        let salt = Data(matchID.uuidString.utf8)
        let info = Data("cacompte.livesession.v1".utf8)
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: inputKeyMaterial, salt: salt, info: info, outputByteCount: 32)
    }

    static func encrypt(_ data: Data, key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw CryptoError.sealFailed }
        return combined
    }

    static func decrypt(_ data: Data, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }
}
