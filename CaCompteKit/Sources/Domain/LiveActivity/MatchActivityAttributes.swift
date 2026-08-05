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
///
/// Doc 09 « Fin de partie » — `matchID`/`gameName`/`gameSymbol` vivent dans `ContentState`, pas
/// dans les attributs fixes : ActivityKit ne permet aucune modification des attributs après
/// `Activity.request`, alors qu'une session de partage peut désormais enchaîner plusieurs parties
/// (voire plusieurs jeux) sans jamais recréer l'Activity — seul un `ContentState` mutable permet
/// de refléter ce changement par un simple push, y compris vers un appareil suspendu qui n'a
/// jamais eu l'occasion de créer une nouvelle Activity pour la partie suivante.
public struct MatchActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public let matchID: UUID
        public let gameName: String
        public let gameSymbol: String
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

        public init(matchID: UUID, gameName: String, gameSymbol: String, roundNumber: Int, standings: [Standing], isStale: Bool = false) {
            self.matchID = matchID
            self.gameName = gameName
            self.gameSymbol = gameSymbol
            self.roundNumber = roundNumber
            self.standings = standings
            self.isStale = isStale
        }
    }

    /// Identifiant opaque et stable pour toute la durée de vie de cette Activity — utile pour le
    /// débogage/les logs, jamais lu pour l'affichage (voir `ContentState` pour tout ce qui varie).
    public let activityKey: String

    public init(activityKey: String) {
        self.activityKey = activityKey
    }
}
#endif
