import Foundation
@testable import Sync

/// Doc 09 « Tests » — un `Transport` en mémoire, sans Wi-Fi ni Bluetooth réels, pour vérifier la
/// convergence de `LiveSession`. Vérifie au passage que le protocole `Transport` est réellement
/// implémentable avant d'écrire une version Wi-Fi ou BLE.

/// Une paire de canaux liés : ce qu'on envoie sur l'un ressort sur `incoming` de l'autre.
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

enum InMemoryTransportError: Error, Sendable {
    case hostUnreachable
}

/// Registre partagé façon « réseau local simulé » : un hôte s'y annonce, un pair y découvre.
actor InMemoryNetwork {
    static let shared = InMemoryNetwork()

    private var advertisements: [UUID: DiscoveredHost] = [:]
    private var acceptors: [UUID: AsyncStream<any TransportSession>.Continuation] = [:]

    func advertise(_ host: DiscoveredHost, acceptor: AsyncStream<any TransportSession>.Continuation) {
        advertisements[host.id] = host
        acceptors[host.id] = acceptor
    }

    func stopAdvertising(_ matchID: UUID) {
        advertisements[matchID] = nil
        acceptors[matchID] = nil
    }

    func currentAdvertisements() -> [DiscoveredHost] {
        Array(advertisements.values)
    }

    func connect(to matchID: UUID) -> (any TransportSession)? {
        guard let acceptor = acceptors[matchID] else { return nil }
        let (hostEnd, peerEnd) = InMemoryChannel.pair()
        acceptor.yield(hostEnd)
        return peerEnd
    }
}

final class InMemoryTransport: Transport, @unchecked Sendable {
    private let deviceName: String
    private let platform: WireMessage.Platform
    private let acceptedStream: AsyncStream<any TransportSession>
    private let acceptedContinuation: AsyncStream<any TransportSession>.Continuation
    private var advertisedMatchID: UUID?

    init(deviceName: String, platform: WireMessage.Platform = .apple) {
        self.deviceName = deviceName
        self.platform = platform
        (acceptedStream, acceptedContinuation) = AsyncStream.makeStream()
    }

    func discover(timeout: Duration) -> AsyncStream<DiscoveredHost> {
        AsyncStream { continuation in
            Task {
                for host in await InMemoryNetwork.shared.currentAdvertisements() {
                    continuation.yield(host)
                }
                continuation.finish()
            }
        }
    }

    func advertise(matchID: UUID, gameID: String, participantCount: Int) async throws {
        advertisedMatchID = matchID
        let host = DiscoveredHost(id: matchID, deviceName: deviceName, gameID: gameID, participantCount: participantCount, platform: platform)
        await InMemoryNetwork.shared.advertise(host, acceptor: acceptedContinuation)
    }

    func stopAdvertising() async {
        guard let advertisedMatchID else { return }
        await InMemoryNetwork.shared.stopAdvertising(advertisedMatchID)
    }

    func acceptIncoming() -> AsyncStream<any TransportSession> {
        acceptedStream
    }

    func connect(to host: DiscoveredHost) async throws -> any TransportSession {
        guard let session = await InMemoryNetwork.shared.connect(to: host.id) else {
            throw InMemoryTransportError.hostUnreachable
        }
        return session
    }
}
