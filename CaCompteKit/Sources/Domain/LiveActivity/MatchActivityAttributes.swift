#if os(iOS)
import ActivityKit
import Foundation

/// Doc utilisateur — Live Activity (roadmap P9) : le score de la partie en cours sur l'écran
/// verrouillé et la Dynamic Island. Défini dans `Domain` (pas dans l'app) pour que la cible
/// widget et la cible app partagent exactement le même type sans dupliquer de fichier entre les
/// deux projets Xcode — les deux dépendent déjà du package `CaCompteKit`. `ActivityAttributes`
/// n'existe pas sur macOS (`Package.swift` déclare aussi cette plateforme, doc roadmap « Après la
/// v1 ») — tout le fichier est donc exclu de ce côté plutôt que de casser le build macOS du
/// package pour un type que rien n'y consomme.
public struct MatchActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public let roundNumber: Int
        public let standings: [Standing]

        public struct Standing: Codable, Hashable, Sendable, Identifiable {
            public let id: UUID
            public let name: String
            public let score: Int

            public init(id: UUID, name: String, score: Int) {
                self.id = id
                self.name = name
                self.score = score
            }
        }

        public init(roundNumber: Int, standings: [Standing]) {
            self.roundNumber = roundNumber
            self.standings = standings
        }
    }

    public let matchID: UUID
    public let gameName: String
    public let gameSymbol: String

    public init(matchID: UUID, gameName: String, gameSymbol: String) {
        self.matchID = matchID
        self.gameName = gameName
        self.gameSymbol = gameSymbol
    }
}
#endif
