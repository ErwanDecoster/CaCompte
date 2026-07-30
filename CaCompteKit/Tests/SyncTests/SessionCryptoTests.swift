import Foundation
import Testing
@testable import Sync

@Suite("SessionCrypto (doc 09 « Appairage et chiffrement »)")
struct SessionCryptoTests {
    @Test("Un message chiffré puis déchiffré avec la même clé redonne l'original")
    func encryptDecryptRoundTrips() throws {
        let matchID = UUID()
        let key = SessionCrypto.deriveKey(pairingCode: "042817", matchID: matchID)
        let plaintext = Data("bonjour".utf8)

        let ciphertext = try SessionCrypto.encrypt(plaintext, key: key)
        let decrypted = try SessionCrypto.decrypt(ciphertext, key: key)

        #expect(decrypted == plaintext)
        #expect(ciphertext != plaintext, "le texte chiffré ne doit jamais coïncider avec le clair")
    }

    @Test("Deux dérivations avec le même code et le même matchID donnent la même clé")
    func deriveKeyIsDeterministic() {
        let matchID = UUID()
        let keyA = SessionCrypto.deriveKey(pairingCode: "042817", matchID: matchID)
        let keyB = SessionCrypto.deriveKey(pairingCode: "042817", matchID: matchID)

        #expect(keyA == keyB)
    }

    @Test("Un matchID différent dérive une clé différente, même code identique")
    func deriveKeyIsSaltedByMatchID() {
        let keyA = SessionCrypto.deriveKey(pairingCode: "042817", matchID: UUID())
        let keyB = SessionCrypto.deriveKey(pairingCode: "042817", matchID: UUID())

        #expect(keyA != keyB)
    }

    @Test("Déchiffrer avec la mauvaise clé échoue plutôt que de renvoyer un résultat corrompu")
    func decryptFailsWithWrongKey() throws {
        let matchID = UUID()
        let rightKey = SessionCrypto.deriveKey(pairingCode: "042817", matchID: matchID)
        let wrongKey = SessionCrypto.deriveKey(pairingCode: "999999", matchID: matchID)
        let ciphertext = try SessionCrypto.encrypt(Data("secret".utf8), key: rightKey)

        #expect(throws: (any Error).self) {
            try SessionCrypto.decrypt(ciphertext, key: wrongKey)
        }
    }
}
