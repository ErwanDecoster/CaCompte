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
        /// Doc utilisateur — remontée : côté pair, la connexion à l'hôte peut tomber (app en
        /// arrière-plan…) sans que la partie soit terminée ; l'affichage se figeait alors sur le
        /// dernier score reçu sans le dire. `true` signale que ce n'est plus mis à jour, plutôt
        /// que de laisser croire à un score en direct qui ne l'est plus.
        public let isStale: Bool

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

        public init(roundNumber: Int, standings: [Standing], isStale: Bool = false) {
            self.roundNumber = roundNumber
            self.standings = standings
            self.isStale = isStale
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
