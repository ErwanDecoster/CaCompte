/// Doc 06 « Badges » — décernés en fin de partie, un par joueur au maximum, purement décoratifs.
public struct Badge: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case winner
        case metronome
        case rollercoaster
        case comeback
        case kamikaze
        case unshakeable
        case photoFinish
    }

    public let kind: Kind
    public let participantID: Participant.ID

    public init(kind: Kind, participantID: Participant.ID) {
        self.kind = kind
        self.participantID = participantID
    }
}
