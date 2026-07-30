public struct InsightID: Sendable, Codable, Hashable, RawRepresentable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

public extension InsightID {
    static let highestRoundScore: InsightID = "highestRoundScore"
    static let bestRoundScore: InsightID = "bestRoundScore"
    static let mostRegular: InsightID = "mostRegular"
    static let mostIrregular: InsightID = "mostIrregular"
    static let finalGap: InsightID = "finalGap"
    static let leadChanges: InsightID = "leadChanges"
    static let longestLeadStreak: InsightID = "longestLeadStreak"
    static let remontada: InsightID = "remontada"
    static let collapse: InsightID = "collapse"
    static let roundsClosed: InsightID = "roundsClosed"
    static let doublingsSuffered: InsightID = "doublingsSuffered"
}

/// Doc 06 — un fait de la partie. `value` porte la donnée brute (vérifiable par golden file,
/// partagée avec Android) ; `headline`/`detail` sont la présentation déjà en français.
public struct Insight: Sendable, Identifiable, Equatable {
    public enum Prominence: Sendable, Equatable {
        case hero, standard, minor
    }

    /// `single` : un fait qui désigne un joueur (et parfois une manche). `global` : un fait sur
    /// la partie entière. `perParticipant` : une valeur par joueur (ex. manches fermées).
    public enum Value: Sendable, Equatable {
        case single(participantID: Participant.ID?, value: Double, round: Int?)
        case perParticipant([Participant.ID: Double])
    }

    public let id: InsightID
    public let headline: String
    public let detail: String
    public let symbol: String
    public let prominence: Prominence
    public let value: Value
    let interestScore: Double

    public init(
        id: InsightID,
        headline: String,
        detail: String,
        symbol: String,
        prominence: Prominence = .standard,
        value: Value,
        interestScore: Double = 0
    ) {
        self.id = id
        self.headline = headline
        self.detail = detail
        self.symbol = symbol
        self.prominence = prominence
        self.value = value
        self.interestScore = interestScore
    }
}
