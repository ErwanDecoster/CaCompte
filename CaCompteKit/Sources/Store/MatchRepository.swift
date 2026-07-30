import Domain
import Foundation
import SwiftData

/// Doc 02 : les écritures interactives restent sur le `mainContext`. `eventLogData` est
/// toujours la source de vérité — chaque écriture réencode le journal complet et rejoue, plutôt
/// que de faire confiance à un total mis en cache (doc 04).
@MainActor
public struct MatchRepository {
    public struct ParticipantSeed {
        public let player: PlayerRecord?
        public let nickname: String
        public let avatarKind: String
        public let avatarValue: String
        public let paletteID: String
        /// Doc 05 « Belote » — `nil` pour tous les jeux individuels.
        public let teamID: String?

        public init(player: PlayerRecord?, nickname: String, avatarKind: String, avatarValue: String, paletteID: String, teamID: String? = nil) {
            self.player = player
            self.nickname = nickname
            self.avatarKind = avatarKind
            self.avatarValue = avatarValue
            self.paletteID = paletteID
            self.teamID = teamID
        }
    }

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func createMatch(
        gameID: String,
        rulesVersion: Int,
        variants: VariantSelection,
        seeds: [ParticipantSeed],
        deviceID: String = "local"
    ) throws -> MatchRecord {
        var participantModels: [ParticipantRecord] = []
        var domainParticipants: [Participant] = []

        for (index, seed) in seeds.enumerated() {
            let id = UUID()
            participantModels.append(ParticipantRecord(
                id: id,
                player: seed.player,
                nicknameSnapshot: seed.nickname,
                avatarKindSnapshot: seed.avatarKind,
                avatarValueSnapshot: seed.avatarValue,
                paletteIDSnapshot: seed.paletteID,
                seatIndex: index,
                teamID: seed.teamID
            ))
            domainParticipants.append(Participant(id: id, displayName: seed.nickname, seatIndex: index, teamID: seed.teamID))
        }

        let createdEvent = StampedEvent(
            lamport: 0,
            deviceID: deviceID,
            occurredAt: Date(),
            event: .matchCreated(gameID: gameID, rulesVersion: rulesVersion, variants: variants, participants: domainParticipants)
        )

        let match = MatchRecord(
            gameID: gameID,
            rulesVersion: rulesVersion,
            variantsData: try JSONEncoder().encode(variants),
            deviceOrigin: deviceID,
            eventLogData: try JSONEncoder().encode([createdEvent]),
            participants: participantModels
        )
        context.insert(match)
        try context.save()
        return match
    }

    public func loadState(_ match: MatchRecord, catalog: GameCatalog) throws -> MatchState {
        let events = try JSONDecoder().decode([StampedEvent].self, from: match.eventLogData)
        return try MatchEngine().replay(events, catalog: catalog)
    }

    @discardableResult
    public func commitRound(
        _ draft: RoundDraft,
        to match: MatchRecord,
        catalog: GameCatalog,
        deviceID: String = "local"
    ) throws -> MatchState {
        try appendEvent(.roundCommitted(draft), to: match, catalog: catalog, deviceID: deviceID)
    }

    @discardableResult
    public func undoLastRound(in match: MatchRecord, catalog: GameCatalog, deviceID: String = "local") throws -> MatchState {
        let events = try JSONDecoder().decode([StampedEvent].self, from: match.eventLogData)
        let lastIndex = events.compactMap { stamped -> Int? in
            if case .roundCommitted(let draft) = stamped.event { return draft.index }
            return nil
        }.max()

        guard let lastIndex else {
            return try loadState(match, catalog: catalog)
        }
        return try appendEvent(.roundRemoved(index: lastIndex), to: match, catalog: catalog, deviceID: deviceID)
    }

    /// Doc 05 « Jeu libre » et tout jeu `manualStop` (Scrabble, Qwirkle…) : `endCheck` ne
    /// détecte jamais cette fin tout seul, elle vient toujours d'une action explicite du joueur.
    @discardableResult
    public func endMatchManually(_ match: MatchRecord, catalog: GameCatalog, deviceID: String = "local") throws -> MatchState {
        try appendEvent(.matchEndedManually, to: match, catalog: catalog, deviceID: deviceID)
    }

    /// Une partie abandonnée reçoit quand même un classement final (calculé sur l'état atteint)
    /// et apparaît dans l'historique — contrairement à une simple suppression, rien n'est perdu.
    @discardableResult
    public func abandonMatch(_ match: MatchRecord, catalog: GameCatalog, deviceID: String = "local") throws -> MatchState {
        try appendEvent(.matchAbandoned(at: Date()), to: match, catalog: catalog, deviceID: deviceID)
    }

    /// Doc 01 « Historique » — masque la partie de la liste sans en perdre la trace : les
    /// statistiques de profil (`ProfileRepository`) continuent de la compter, seul l'onglet
    /// Historique la filtre. Même mécanisme que `PlayerRepository.archive`.
    public func archive(_ match: MatchRecord) throws {
        match.isArchived = true
        try context.save()
    }

    public func unarchive(_ match: MatchRecord) throws {
        match.isArchived = false
        try context.save()
    }

    /// Suppression définitive — irréversible, contrairement à `archive`. Cascade sur
    /// `ParticipantRecord` (doc 03) : ces lignes de statistiques disparaissent avec la partie,
    /// contrairement à `PlayerRepository.delete` qui, lui, laisse l'historique intact.
    public func delete(_ match: MatchRecord) throws {
        context.delete(match)
        try context.save()
    }

    public func inProgressMatches() throws -> [MatchRecord] {
        let descriptor = FetchDescriptor<MatchRecord>(
            predicate: #Predicate { $0.statusRaw == "inProgress" || $0.statusRaw == "finalRound" }
        )
        return try context.fetch(descriptor)
    }

    /// Aucune partie jamais créée, terminée ou non — sert à distinguer « premier lancement ».
    public func hasAnyMatch() throws -> Bool {
        var descriptor = FetchDescriptor<MatchRecord>()
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    /// Doc 01 « Historique » — parties terminées ou abandonnées, les plus récentes d'abord. Les
    /// filtres par jeu/joueur restent en mémoire côté appelant (doc 06 : le volume attendu ne
    /// justifie pas des prédicats composés).
    public func finishedMatches() throws -> [MatchRecord] {
        let descriptor = FetchDescriptor<MatchRecord>(
            predicate: #Predicate { !$0.isArchived && ($0.statusRaw == "ended" || $0.statusRaw == "abandoned") },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// Parties masquées de l'Historique via `archive(_:)` — écran séparé, même logique que
    /// `ArchivedPlayersView` pour les joueurs.
    public func archivedMatches() throws -> [MatchRecord] {
        let descriptor = FetchDescriptor<MatchRecord>(
            predicate: #Predicate { $0.isArchived },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// Joueurs de la dernière partie jouée à ce jeu (terminée ou abandonnée), dans l'ordre des
    /// sièges — sert à pré-sélectionner les habitués à la mise en place d'une nouvelle partie.
    /// Vide si ce jeu n'a jamais été joué (l'appelant retombe alors sur un autre critère, ex.
    /// les joueurs créés le plus récemment).
    public func mostRecentParticipants(forGameID gameID: String) throws -> [PlayerRecord] {
        var descriptor = FetchDescriptor<MatchRecord>(
            predicate: #Predicate { $0.gameID == gameID && ($0.statusRaw == "ended" || $0.statusRaw == "abandoned") },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let lastMatch = try context.fetch(descriptor).first else { return [] }
        return lastMatch.participants
            .sorted { $0.seatIndex < $1.seatIndex }
            .compactMap(\.player)
    }

    /// Doc 09 — le journal complet d'une partie, tel que `LiveSession` en a besoin pour s'y
    /// resynchroniser (`syncHostLog`) ou pour accueillir un nouveau pair (`welcome`).
    public func currentLog(for match: MatchRecord) throws -> [StampedEvent] {
        try JSONDecoder().decode([StampedEvent].self, from: match.eventLogData)
    }

    /// Doc 09 « hôte autoritaire » — persiste un événement déjà validé et horodaté par
    /// `LiveSession` (une manche acceptée d'un contributeur distant), plutôt que d'en construire
    /// un nouveau comme le fait `appendEvent`. Idempotent par `id` : un événement redélivré par
    /// le réseau ne s'applique pas deux fois (doc 09 « Tests », ADR-0005).
    @discardableResult
    public func appendRemoteEvent(_ stamped: StampedEvent, to match: MatchRecord, catalog: GameCatalog) throws -> MatchState {
        var events = try currentLog(for: match)
        guard !events.contains(where: { $0.id == stamped.id }) else {
            return try MatchEngine().replay(events, catalog: catalog)
        }
        events.append(stamped)
        return try persist(events, to: match, catalog: catalog)
    }

    @discardableResult
    private func appendEvent(
        _ event: MatchEvent,
        to match: MatchRecord,
        catalog: GameCatalog,
        deviceID: String
    ) throws -> MatchState {
        var events = try currentLog(for: match)
        let nextLamport = (events.map(\.lamport).max() ?? 0) + 1
        events.append(StampedEvent(lamport: nextLamport, deviceID: deviceID, occurredAt: Date(), event: event))
        return try persist(events, to: match, catalog: catalog)
    }

    private func persist(_ events: [StampedEvent], to match: MatchRecord, catalog: GameCatalog) throws -> MatchState {
        match.eventLogData = try JSONEncoder().encode(events)

        let state = try MatchEngine().replay(events, catalog: catalog)
        match.statusRaw = state.status.rawValue
        match.endReasonRaw = state.endReason?.rawValue

        if state.status == .ended || state.status == .abandoned {
            match.endedAt = Date()
            applyFinalStandings(state: state, match: match, catalog: catalog)
        } else {
            match.endedAt = nil
        }

        try context.save()
        return state
    }

    private func applyFinalStandings(state: MatchState, match: MatchRecord, catalog: GameCatalog) {
        guard let definition = try? catalog.definition(for: match.gameID, version: match.rulesVersion),
              let rules = try? catalog.rules(for: match.gameID, version: match.rulesVersion) else { return }

        let standingsByID = Dictionary(uniqueKeysWithValues: rules.standings(state, definition: definition).map { ($0.participantID, $0) })
        for participant in match.participants {
            guard let standing = standingsByID[participant.id] else { continue }
            participant.finalRank = standing.rank
            participant.finalScore = standing.score
        }
    }
}
