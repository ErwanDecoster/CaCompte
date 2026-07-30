/// Doc 09 — trois rôles possibles dans une partie partagée. `.host` n'est jamais demandé par un
/// pair qui rejoint, seuls `.contributor` et `.observer` transitent sur le fil.
public enum Role: String, Codable, Sendable, Equatable {
    case host
    case contributor
    case observer
}
