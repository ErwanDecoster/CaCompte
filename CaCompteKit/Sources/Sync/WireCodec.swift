import CryptoKit
import Foundation

/// `WireMessage` encodé en JSON puis chiffré (doc 09) — la seule forme qui transite sur un
/// `TransportSession`, quel que soit le transport actif.
enum WireCodec {
    static func encode(_ message: WireMessage, key: SymmetricKey) throws -> Data {
        let json = try JSONEncoder().encode(message)
        return try SessionCrypto.encrypt(json, key: key)
    }

    static func decode(_ data: Data, key: SymmetricKey) throws -> WireMessage {
        let json = try SessionCrypto.decrypt(data, key: key)
        return try JSONDecoder().decode(WireMessage.self, from: json)
    }
}
