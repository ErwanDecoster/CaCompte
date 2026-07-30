/// Définition déclarative d'un jeu — transposition mécanique de
/// `spec/schema/game-definition.schema.json`. Couvre tout ce qui est exprimable en données ;
/// le calcul non trivial est délégué au moteur impératif désigné par `engine`.
public struct GameDefinition: Identifiable, Sendable, Codable, Equatable {
    public struct LocalizedText: Sendable, Codable, Equatable {
        public let fr: String
        public let en: String?

        public init(fr: String, en: String? = nil) {
            self.fr = fr
            self.en = en
        }
    }

    public enum PaletteToken: String, Sendable, Codable, Equatable {
        case ink, brass, teal, azur, ambre, emeraude, magenta, ardoise, cyan, vermillon, violet, olive
    }

    public struct Players: Sendable, Codable, Equatable {
        public struct Teams: Sendable, Codable, Equatable {
            public let size: Int
            public let fixed: Bool

            private enum CodingKeys: String, CodingKey { case size, fixed }

            public init(size: Int, fixed: Bool = true) {
                self.size = size
                self.fixed = fixed
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                size = try container.decode(Int.self, forKey: .size)
                fixed = try container.decodeIfPresent(Bool.self, forKey: .fixed) ?? true
            }
        }

        public let min: Int
        public let max: Int
        public let recommended: [Int]
        public let teams: Teams?

        private enum CodingKeys: String, CodingKey { case min, max, recommended, teams }

        public init(min: Int, max: Int, recommended: [Int] = [], teams: Teams? = nil) {
            self.min = min
            self.max = max
            self.recommended = recommended
            self.teams = teams
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            min = try container.decode(Int.self, forKey: .min)
            max = try container.decode(Int.self, forKey: .max)
            recommended = try container.decodeIfPresent([Int].self, forKey: .recommended) ?? []
            teams = try container.decodeIfPresent(Teams.self, forKey: .teams)
        }
    }

    public enum EntryKind: String, Sendable, Codable, Equatable {
        case integer, categorySheet, structured, rank, predictionAndResult
    }

    public struct Category: Sendable, Codable, Equatable {
        public enum Section: String, Sendable, Codable, Equatable { case upper, lower }

        public struct Scoring: Sendable, Codable, Equatable {
            public enum Kind: String, Sendable, Codable, Equatable { case fixed, sumOfDice, multipleOf }
            public let kind: Kind
            public let value: Int?
            public let max: Int?

            public init(kind: Kind, value: Int? = nil, max: Int? = nil) {
                self.kind = kind
                self.value = value
                self.max = max
            }
        }

        public let id: String
        public let label: LocalizedText
        public let section: Section
        public let scoring: Scoring

        public init(id: String, label: LocalizedText, section: Section, scoring: Scoring) {
            self.id = id
            self.label = label
            self.section = section
            self.scoring = scoring
        }
    }

    public struct RankOption: Sendable, Codable, Equatable {
        public let id: String
        public let label: LocalizedText
        public let points: Int

        public init(id: String, label: LocalizedText, points: Int) {
            self.id = id
            self.label = label
            self.points = points
        }
    }

    public struct ScoreEntrySpec: Sendable, Codable, Equatable {
        public let kind: EntryKind
        public let min: Int?
        public let max: Int?
        public let step: Int
        public let allowsNegative: Bool
        public let warnBelow: Int?
        public let warnAbove: Int?
        public let categories: [Category]?
        public let ranks: [RankOption]?

        private enum CodingKeys: String, CodingKey {
            case kind, min, max, step, allowsNegative, warnBelow, warnAbove, categories, ranks
        }

        public init(
            kind: EntryKind,
            min: Int? = nil,
            max: Int? = nil,
            step: Int = 1,
            allowsNegative: Bool = false,
            warnBelow: Int? = nil,
            warnAbove: Int? = nil,
            categories: [Category]? = nil,
            ranks: [RankOption]? = nil
        ) {
            self.kind = kind
            self.min = min
            self.max = max
            self.step = step
            self.allowsNegative = allowsNegative
            self.warnBelow = warnBelow
            self.warnAbove = warnAbove
            self.categories = categories
            self.ranks = ranks
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decode(EntryKind.self, forKey: .kind)
            min = try container.decodeIfPresent(Int.self, forKey: .min)
            max = try container.decodeIfPresent(Int.self, forKey: .max)
            step = try container.decodeIfPresent(Int.self, forKey: .step) ?? 1
            allowsNegative = try container.decodeIfPresent(Bool.self, forKey: .allowsNegative) ?? false
            warnBelow = try container.decodeIfPresent(Int.self, forKey: .warnBelow)
            warnAbove = try container.decodeIfPresent(Int.self, forKey: .warnAbove)
            categories = try container.decodeIfPresent([Category].self, forKey: .categories)
            ranks = try container.decodeIfPresent([RankOption].self, forKey: .ranks)
        }
    }

    public enum ModifierKind: String, Sendable, Codable, Equatable {
        case exclusiveFlag, flag, counter
    }

    public struct Modifier: Sendable, Codable, Equatable {
        public let id: String
        public let label: LocalizedText
        public let kind: ModifierKind
        public let required: Bool
        public let max: Int?

        private enum CodingKeys: String, CodingKey { case id, label, kind, required, max }

        public init(id: String, label: LocalizedText, kind: ModifierKind, required: Bool = false, max: Int? = nil) {
            self.id = id
            self.label = label
            self.kind = kind
            self.required = required
            self.max = max
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            label = try container.decode(LocalizedText.self, forKey: .label)
            kind = try container.decode(ModifierKind.self, forKey: .kind)
            required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
            max = try container.decodeIfPresent(Int.self, forKey: .max)
        }
    }

    public enum Direction: String, Sendable, Codable, Equatable {
        case lowestWins, highestWins, targetExact
    }

    public enum Aggregation: String, Sendable, Codable, Equatable {
        case cumulative, lastRoundOnly, bestRound
    }

    public struct Scoring: Sendable, Codable, Equatable {
        public let direction: Direction
        public let aggregation: Aggregation
        public let roundLabel: LocalizedText?
        public let entry: ScoreEntrySpec
        public let modifiers: [Modifier]

        private enum CodingKeys: String, CodingKey {
            case direction, aggregation, roundLabel, entry, modifiers
        }

        public init(
            direction: Direction,
            aggregation: Aggregation = .cumulative,
            roundLabel: LocalizedText? = nil,
            entry: ScoreEntrySpec,
            modifiers: [Modifier] = []
        ) {
            self.direction = direction
            self.aggregation = aggregation
            self.roundLabel = roundLabel
            self.entry = entry
            self.modifiers = modifiers
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            direction = try container.decode(Direction.self, forKey: .direction)
            aggregation = try container.decodeIfPresent(Aggregation.self, forKey: .aggregation) ?? .cumulative
            roundLabel = try container.decodeIfPresent(LocalizedText.self, forKey: .roundLabel)
            entry = try container.decode(ScoreEntrySpec.self, forKey: .entry)
            modifiers = try container.decodeIfPresent([Modifier].self, forKey: .modifiers) ?? []
        }
    }

    public enum EndConditionType: String, Sendable, Codable, Equatable {
        case scoreThreshold, roundLimit, targetReached, allSheetsComplete, elimination, manualStop
    }

    public enum Comparison: String, Sendable, Codable, Equatable {
        case greaterThanOrEqual = ">="
        case greaterThan = ">"
        case equalTo = "=="
        case lessThanOrEqual = "<="
        case lessThan = "<"

        public func evaluate(_ lhs: Int, _ rhs: Int) -> Bool {
            switch self {
            case .greaterThanOrEqual: lhs >= rhs
            case .greaterThan: lhs > rhs
            case .equalTo: lhs == rhs
            case .lessThanOrEqual: lhs <= rhs
            case .lessThan: lhs < rhs
            }
        }
    }

    public enum Scope: String, Sendable, Codable, Equatable {
        case anyPlayer, allPlayers, anyTeam
    }

    public struct EndCondition: Sendable, Codable, Equatable {
        public let type: EndConditionType
        public let value: Int?
        public let valueExpression: String?
        public let comparison: Comparison
        public let scope: Scope
        public let completeRound: Bool
        public let variantKey: String?

        private enum CodingKeys: String, CodingKey {
            case type, value, valueExpression, comparison, scope, completeRound, variantKey
        }

        public init(
            type: EndConditionType,
            value: Int? = nil,
            valueExpression: String? = nil,
            comparison: Comparison = .greaterThanOrEqual,
            scope: Scope = .anyPlayer,
            completeRound: Bool = true,
            variantKey: String? = nil
        ) {
            self.type = type
            self.value = value
            self.valueExpression = valueExpression
            self.comparison = comparison
            self.scope = scope
            self.completeRound = completeRound
            self.variantKey = variantKey
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(EndConditionType.self, forKey: .type)
            value = try container.decodeIfPresent(Int.self, forKey: .value)
            valueExpression = try container.decodeIfPresent(String.self, forKey: .valueExpression)
            comparison = try container.decodeIfPresent(Comparison.self, forKey: .comparison) ?? .greaterThanOrEqual
            scope = try container.decodeIfPresent(Scope.self, forKey: .scope) ?? .anyPlayer
            completeRound = try container.decodeIfPresent(Bool.self, forKey: .completeRound) ?? true
            variantKey = try container.decodeIfPresent(String.self, forKey: .variantKey)
        }

        /// `value`, remplacé par la variante choisie si `variantKey` est présent.
        public func resolvedValue(variants: VariantSelection) -> Int {
            if let variantKey {
                return variants.int(variantKey, default: value ?? 0)
            }
            return value ?? 0
        }
    }

    public struct End: Sendable, Codable, Equatable {
        public let conditions: [EndCondition]

        public init(conditions: [EndCondition]) {
            self.conditions = conditions
        }
    }

    public enum TieBreakRule: String, Sendable, Codable, Equatable {
        case bestSingleRound, worstSingleRound, fewestRoundsClosed, mostRoundsWon
        case lowerSecondaryScore, higherSecondaryScore, headToHead, shared
    }

    public enum VariantKind: String, Sendable, Codable, Equatable {
        case bool, integerChoice, integerRange, option
    }

    public struct Variant: Sendable, Codable, Equatable {
        public let id: String
        public let label: LocalizedText
        public let help: LocalizedText?
        public let kind: VariantKind
        public let values: [VariantSelection.Value]
        public let min: Int?
        public let max: Int?
        public let defaultValue: VariantSelection.Value

        private enum CodingKeys: String, CodingKey {
            case id, label, help, kind, values, min, max
            case defaultValue = "default"
        }

        public init(
            id: String,
            label: LocalizedText,
            help: LocalizedText? = nil,
            kind: VariantKind,
            values: [VariantSelection.Value] = [],
            min: Int? = nil,
            max: Int? = nil,
            defaultValue: VariantSelection.Value
        ) {
            self.id = id
            self.label = label
            self.help = help
            self.kind = kind
            self.values = values
            self.min = min
            self.max = max
            self.defaultValue = defaultValue
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            label = try container.decode(LocalizedText.self, forKey: .label)
            help = try container.decodeIfPresent(LocalizedText.self, forKey: .help)
            kind = try container.decode(VariantKind.self, forKey: .kind)
            values = try container.decodeIfPresent([VariantSelection.Value].self, forKey: .values) ?? []
            min = try container.decodeIfPresent(Int.self, forKey: .min)
            max = try container.decodeIfPresent(Int.self, forKey: .max)
            defaultValue = try container.decode(VariantSelection.Value.self, forKey: .defaultValue)
        }
    }

    public let id: String
    public let specVersion: Int
    public let rulesVersion: Int
    public let name: LocalizedText
    public let shortDescription: LocalizedText?
    public let symbol: String
    public let paletteID: PaletteToken
    public let players: Players
    public let scoring: Scoring
    public let engine: String
    public let end: End
    public let tieBreak: [TieBreakRule]
    public let variants: [Variant]
    public let statsProfiles: [String]

    private enum CodingKeys: String, CodingKey {
        case id, specVersion, rulesVersion, name, shortDescription, symbol, paletteID
        case players, scoring, engine, end, tieBreak, variants, statsProfiles
    }

    public init(
        id: String,
        specVersion: Int,
        rulesVersion: Int,
        name: LocalizedText,
        shortDescription: LocalizedText? = nil,
        symbol: String,
        paletteID: PaletteToken = .ink,
        players: Players,
        scoring: Scoring,
        engine: String,
        end: End,
        tieBreak: [TieBreakRule] = [.shared],
        variants: [Variant] = [],
        statsProfiles: [String] = ["standard"]
    ) {
        self.id = id
        self.specVersion = specVersion
        self.rulesVersion = rulesVersion
        self.name = name
        self.shortDescription = shortDescription
        self.symbol = symbol
        self.paletteID = paletteID
        self.players = players
        self.scoring = scoring
        self.engine = engine
        self.end = end
        self.tieBreak = tieBreak
        self.variants = variants
        self.statsProfiles = statsProfiles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        specVersion = try container.decode(Int.self, forKey: .specVersion)
        rulesVersion = try container.decode(Int.self, forKey: .rulesVersion)
        name = try container.decode(LocalizedText.self, forKey: .name)
        shortDescription = try container.decodeIfPresent(LocalizedText.self, forKey: .shortDescription)
        symbol = try container.decode(String.self, forKey: .symbol)
        paletteID = try container.decodeIfPresent(PaletteToken.self, forKey: .paletteID) ?? .ink
        players = try container.decode(Players.self, forKey: .players)
        scoring = try container.decode(Scoring.self, forKey: .scoring)
        engine = try container.decode(String.self, forKey: .engine)
        end = try container.decode(End.self, forKey: .end)
        tieBreak = try container.decodeIfPresent([TieBreakRule].self, forKey: .tieBreak) ?? [.shared]
        variants = try container.decodeIfPresent([Variant].self, forKey: .variants) ?? []
        statsProfiles = try container.decodeIfPresent([String].self, forKey: .statsProfiles) ?? ["standard"]
    }
}

public typealias Direction = GameDefinition.Direction
public typealias TieBreakRule = GameDefinition.TieBreakRule
