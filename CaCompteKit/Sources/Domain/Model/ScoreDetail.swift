import Foundation

/// Payload structuré propre à un jeu (grille Yams, contrat Tarot…). Opaque au moteur générique
/// et à `Skyjo` — aucun des deux ne l'utilise. Contenu détaillé lors de l'arrivée d'un jeu qui
/// en a besoin (Phase 7).
public struct ScoreDetail: Sendable, Codable, Equatable {
    public let payload: Data

    public init(payload: Data) {
        self.payload = payload
    }
}
