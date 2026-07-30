import Foundation

/// Doc 06 « Statistiques de profil » — agrégées sur tout l'historique d'un joueur.
public struct ProfileStats: Sendable, Equatable {
    public struct GameBreakdown: Sendable, Equatable {
        public let gameID: String
        public let gameName: String
        public let played: Int
        public let wins: Int
        public let winRate: Double
        /// Le score personnel le plus favorable (selon le sens du jeu) et sa date.
        public let bestScore: (value: Int, date: Date)?
        /// Le score personnel le moins favorable et sa date.
        public let worstScore: (value: Int, date: Date)?

        public init(
            gameID: String,
            gameName: String,
            played: Int,
            wins: Int,
            winRate: Double,
            bestScore: (value: Int, date: Date)?,
            worstScore: (value: Int, date: Date)?
        ) {
            self.gameID = gameID
            self.gameName = gameName
            self.played = played
            self.wins = wins
            self.winRate = winRate
            self.bestScore = bestScore
            self.worstScore = worstScore
        }

        public static func == (lhs: GameBreakdown, rhs: GameBreakdown) -> Bool {
            lhs.gameID == rhs.gameID && lhs.gameName == rhs.gameName && lhs.played == rhs.played
                && lhs.wins == rhs.wins && lhs.winRate == rhs.winRate
                && lhs.bestScore?.value == rhs.bestScore?.value && lhs.bestScore?.date == rhs.bestScore?.date
                && lhs.worstScore?.value == rhs.worstScore?.value && lhs.worstScore?.date == rhs.worstScore?.date
        }
    }

    /// Doc 06 : « adversaire rencontré au moins 5 fois contre qui le taux de victoire est le
    /// plus faible ». Le taux de victoire s'entend ici comme ailleurs : la part de parties
    /// gagnées (rang 1) parmi celles jouées ensemble — pas un score tête-à-tête séparé.
    public struct Nemesis: Sendable, Equatable {
        public let playerID: UUID
        public let name: String
        public let matchesTogether: Int
        public let winRateWithThemPresent: Double

        public init(playerID: UUID, name: String, matchesTogether: Int, winRateWithThemPresent: Double) {
            self.playerID = playerID
            self.name = name
            self.matchesTogether = matchesTogether
            self.winRateWithThemPresent = winRateWithThemPresent
        }
    }

    public struct MonthActivity: Sendable, Equatable, Identifiable {
        public var id: String { monthKey }
        /// Format `yyyy-MM`, pour un tri et un affichage stables indépendants du fuseau horaire.
        public let monthKey: String
        public let count: Int

        public init(monthKey: String, count: Int) {
            self.monthKey = monthKey
            self.count = count
        }
    }

    public let played: Int
    public let wins: Int
    public let winRate: Double
    public let averageRank: Double
    /// `(nbJoueurs − rang) / (nbJoueurs − 1)`, moyenné — comparable entre parties à effectifs
    /// différents (doc 06 : gagner à 2 n'est pas gagner à 8).
    public let averageNormalizedRank: Double
    public let byGame: [GameBreakdown]
    public let nemesis: Nemesis?
    public let currentWinStreak: Int
    public let bestWinStreak: Int
    /// 12 derniers mois, ordre chronologique, mois sans partie inclus à zéro.
    public let activity: [MonthActivity]

    public init(
        played: Int,
        wins: Int,
        winRate: Double,
        averageRank: Double,
        averageNormalizedRank: Double,
        byGame: [GameBreakdown],
        nemesis: Nemesis?,
        currentWinStreak: Int,
        bestWinStreak: Int,
        activity: [MonthActivity]
    ) {
        self.played = played
        self.wins = wins
        self.winRate = winRate
        self.averageRank = averageRank
        self.averageNormalizedRank = averageNormalizedRank
        self.byGame = byGame
        self.nemesis = nemesis
        self.currentWinStreak = currentWinStreak
        self.bestWinStreak = bestWinStreak
        self.activity = activity
    }

    public static let empty = ProfileStats(
        played: 0, wins: 0, winRate: 0, averageRank: 0, averageNormalizedRank: 0,
        byGame: [], nemesis: nil, currentWinStreak: 0, bestWinStreak: 0, activity: []
    )
}
