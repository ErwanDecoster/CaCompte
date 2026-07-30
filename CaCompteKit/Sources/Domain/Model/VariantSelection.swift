/// Options choisies pour une partie donnée, ex. `{"threshold": 100, "doublePenalty": true}`.
/// Décodée directement comme un objet JSON à valeurs mixtes (entier, booléen, chaîne).
public struct VariantSelection: Sendable, Codable, Equatable {
    public enum Value: Sendable, Codable, Equatable {
        case int(Int)
        case bool(Bool)
        case string(String)

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let boolValue = try? container.decode(Bool.self) {
                self = .bool(boolValue)
            } else if let intValue = try? container.decode(Int.self) {
                self = .int(intValue)
            } else {
                self = .string(try container.decode(String.self))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .int(let value): try container.encode(value)
            case .bool(let value): try container.encode(value)
            case .string(let value): try container.encode(value)
            }
        }
    }

    private let values: [String: Value]

    public init(_ values: [String: Value] = [:]) {
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        values = try container.decode([String: Value].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }

    public func bool(_ key: String, default defaultValue: Bool) -> Bool {
        guard case .bool(let value) = values[key] else { return defaultValue }
        return value
    }

    public func int(_ key: String, default defaultValue: Int) -> Int {
        guard case .int(let value) = values[key] else { return defaultValue }
        return value
    }

    public func string(_ key: String, default defaultValue: String) -> String {
        guard case .string(let value) = values[key] else { return defaultValue }
        return value
    }
}

extension VariantSelection: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, Value)...) {
        self.init(Dictionary(uniqueKeysWithValues: elements))
    }
}
