import Foundation

public struct MatchEngine: Sendable {
    /// Injectée plutôt qu'un `Date()` implicite (doc 02) : `reduce` reste une fonction pure et
    /// reproductible, y compris rejouée deux fois dans un test.
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    /// `(MatchState, MatchEvent) -> MatchState` pure — fondement de l'annulation (on retire
    /// l'événement, on rejoue) et de la synchronisation (on fusionne deux journaux, on rejoue).
    public func reduce(_ state: MatchState, _ event: MatchEvent, rules: any GameRules, definition: GameDefinition) -> MatchState {
        var newState = state
        newState.apply(event, rules: rules, definition: definition, occurredAt: now())
        return newState
    }

    /// Dédoublonne par `id`, trie par `(lamport, deviceID)`, replie. Commutatif et idempotent :
    /// `replay(L) == replay(σ(L))` et `replay(L + L) == replay(L)`.
    public func replay(_ log: [StampedEvent], catalog: GameCatalog) throws -> MatchState {
        var seen = Set<UUID>()
        let deduplicated = log.filter { seen.insert($0.id).inserted }
        let sorted = deduplicated.sorted { lhs, rhs in
            lhs.lamport != rhs.lamport ? lhs.lamport < rhs.lamport : lhs.deviceID < rhs.deviceID
        }

        guard let first = sorted.first,
              case .matchCreated(let gameID, let rulesVersion, let variants, let participants) = first.event else {
            throw MatchEngineError.missingMatchCreated
        }

        let definition = try catalog.definition(for: gameID, version: rulesVersion)
        let rules = try catalog.rules(for: gameID, version: rulesVersion)

        var state = MatchState(
            matchID: first.id,
            gameID: gameID,
            rulesVersion: rulesVersion,
            variants: variants,
            participants: participants
        )
        for stamped in sorted.dropFirst() {
            state.apply(stamped.event, rules: rules, definition: definition, occurredAt: stamped.occurredAt)
        }
        return state
    }
}

public enum MatchEngineError: Error, Sendable, Equatable {
    case missingMatchCreated
}
