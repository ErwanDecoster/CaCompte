public enum ValidationResult: Sendable, Equatable {
    case valid
    case warning([String])
    case invalid([ValidationError])
}

public struct ValidationError: Sendable, Equatable {
    public enum Field: Sendable, Equatable {
        case participant(Participant.ID)
        case modifier(ModifierID)
        case general
    }

    public let field: Field
    public let message: String

    public init(field: Field, message: String) {
        self.field = field
        self.message = message
    }
}
