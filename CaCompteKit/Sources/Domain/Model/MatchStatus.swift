public enum MatchStatus: String, Sendable, Codable, Equatable {
    case inProgress
    case finalRound
    case ended
    case abandoned
}
