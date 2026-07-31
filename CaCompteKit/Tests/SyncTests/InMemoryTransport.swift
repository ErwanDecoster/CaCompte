import Foundation
@testable import Sync

/// Doc 09 « Tests », révisé P9 — une paire de `TransportSession` en mémoire, pour vérifier la
/// convergence de `LiveSession` sans dépendre d'un vrai transport (Supabase Realtime). Ce qu'on
/// envoie sur l'un ressort sur `incoming` de l'autre.
///
/// Construits atomiquement par `pair()`, sans passer par un acteur : rien n'est mutable après
/// la construction, `@unchecked Sendable` est donc sûr.
final class InMemoryChannel: TransportSession, @unchecked Sendable {
    let incoming: AsyncStream<Data>
    private let outgoing: AsyncStream<Data>.Continuation

    private init(incoming: AsyncStream<Data>, outgoing: AsyncStream<Data>.Continuation) {
        self.incoming = incoming
        self.outgoing = outgoing
    }

    static func pair() -> (InMemoryChannel, InMemoryChannel) {
        let (streamA, continuationA) = AsyncStream<Data>.makeStream()
        let (streamB, continuationB) = AsyncStream<Data>.makeStream()
        let endA = InMemoryChannel(incoming: streamA, outgoing: continuationB)
        let endB = InMemoryChannel(incoming: streamB, outgoing: continuationA)
        return (endA, endB)
    }

    func send(_ data: Data) async throws {
        outgoing.yield(data)
    }

    func close() async {
        outgoing.finish()
    }
}
