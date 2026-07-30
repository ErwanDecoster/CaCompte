public struct ModifierID: Sendable, Codable, Hashable, RawRepresentable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

public extension ModifierID {
    static let closedRound: ModifierID = "closedRound"
}
