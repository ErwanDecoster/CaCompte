import Foundation
import Network

/// Doc 09 / ADR-0014 — transport principal : découverte mDNS/DNS-SD (`_cacompte._tcp`, un
/// standard IETF que iOS et Android implémentent tous deux nativement) et transport par socket
/// TCP tramé (préfixe de longueur 4 octets). Aucune dépendance tierce (ADR-0012) : tout vient de
/// `Network.framework` et de `NetService`/`NetServiceBrowser` (Foundation), tous deux système.
///
/// **Pourquoi deux API Apple plutôt qu'une seule.** `NWListener.Service`/`NWBrowser` (l'API la
/// plus récente) ne remontait pas les enregistrements TXT dans cet environnement — confirmé par
/// un harnais de diagnostic isolé, alors que `dns-sd` au niveau système résolvait le même
/// enregistrement TXT sans problème. `NetService`/`NetServiceBrowser` (l'API Bonjour historique)
/// le fait de façon fiable. Le transport lui-même (`NWListener`/`NWConnection`) reste sur
/// `Network.framework`, qui n'a pas cette limite : `NetService` ne sert qu'à la découverte et au
/// TXT record, jamais à transporter la moindre donnée.
///
/// Callbacks toujours reçus sur `.main` (Network.framework comme les délégués `NetService*`) —
/// c'est ce qui rend les mutations internes sûres malgré `@unchecked Sendable` : un seul point
/// d'entrée séquentiel, jamais deux threads concurrents.
public final class WifiTransport: Transport, @unchecked Sendable {
    private static let serviceType = "_cacompte._tcp."
    private static let domain = "local."

    private let deviceName: String
    private let platform: WireMessage.Platform

    private var listener: NWListener?
    private var advertisedService: NetService?
    private var publishDelegate: PublishDelegate?

    private let acceptedStream: AsyncStream<any TransportSession>
    private let acceptedContinuation: AsyncStream<any TransportSession>.Continuation

    public init(deviceName: String, platform: WireMessage.Platform = .apple) {
        self.deviceName = deviceName
        self.platform = platform
        (acceptedStream, acceptedContinuation) = AsyncStream.makeStream()
    }

    public func advertise(matchID: UUID, gameID: String, participantCount: Int) async throws {
        let newListener = try NWListener(using: .tcp)
        newListener.newConnectionHandler = { [acceptedContinuation] connection in
            connection.start(queue: .main)
            acceptedContinuation.yield(WifiTransportSession(connection: connection))
        }
        listener = newListener

        // `stateUpdateHandler` continue de recevoir des changements d'état bien après ce premier
        // aller-retour (l'app passe en arrière-plan, le réseau coupe) — une `CheckedContinuation`
        // ne tolère qu'une seule résolution, une deuxième provoque un crash immédiat. D'où le
        // retrait du handler dès qu'elle a été résolue une fois, sur toutes les branches.
        let port = try await withCheckedThrowingContinuation { (checked: CheckedContinuation<NWEndpoint.Port, Error>) in
            newListener.stateUpdateHandler = { [weak newListener] state in
                switch state {
                case .ready:
                    newListener?.stateUpdateHandler = nil
                    if let port = newListener?.port {
                        checked.resume(returning: port)
                    } else {
                        checked.resume(throwing: WifiTransportError.connectionFailed)
                    }
                case .failed(let error):
                    newListener?.stateUpdateHandler = nil
                    checked.resume(throwing: error)
                case .cancelled:
                    newListener?.stateUpdateHandler = nil
                    checked.resume(throwing: WifiTransportError.connectionFailed)
                default:
                    break
                }
            }
            newListener.start(queue: .main)
        }

        let service = NetService(domain: Self.domain, type: Self.serviceType, name: matchID.uuidString, port: Int32(port.rawValue))
        service.setTXTRecord(Self.txtRecordData(gameID: gameID, participantCount: participantCount, deviceName: deviceName, platform: platform))
        let delegate = PublishDelegate()
        service.delegate = delegate
        publishDelegate = delegate
        advertisedService = service
        service.publish()
    }

    public func stopAdvertising() async {
        advertisedService?.stop()
        advertisedService = nil
        publishDelegate = nil
        listener?.cancel()
        listener = nil
    }

    public func acceptIncoming() -> AsyncStream<any TransportSession> {
        acceptedStream
    }

    public func discover(timeout: Duration) -> AsyncStream<DiscoveredHost> {
        AsyncStream { continuation in
            let delegate = BrowseDelegate { host in continuation.yield(host) }
            let newBrowser = NetServiceBrowser()
            newBrowser.delegate = delegate
            newBrowser.searchForServices(ofType: Self.serviceType, inDomain: Self.domain)

            // `NetServiceBrowser` n'est pas `Sendable` (API historique, pré-Swift-concurrency) ;
            // la boîte l'autorise à traverser les fermetures `@Sendable` ci-dessous sans jamais
            // muter quoi que ce soit hors de la queue `.main` où tout ce fichier s'exécute.
            let browserBox = UncheckedBox(newBrowser)

            let task = Task {
                try? await Task.sleep(for: timeout)
                browserBox.value.stop()
                continuation.finish()
            }
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                browserBox.value.stop()
                self?.activeBrowses.removeAll { $0.0 === browserBox.value }
            }
            // Retient le navigateur et son délégué pour la durée de vie du flux — sans quoi ARC
            // les libère dès la sortie de cette fermeture et la découverte ne renvoie jamais rien.
            self.activeBrowses.append((newBrowser, delegate))
        }
    }

    public func connect(to host: DiscoveredHost) async throws -> any TransportSession {
        guard let endpoint = activeBrowses.lazy.compactMap({ $0.1.endpoint(for: host.id) }).first else {
            throw WifiTransportError.hostNotFound
        }
        let connection = NWConnection(to: endpoint, using: .tcp)
        let session = WifiTransportSession(connection: connection)
        connection.start(queue: .main)
        try await session.waitUntilReady()
        return session
    }

    /// Garde vivants les navigateurs Bonjour en cours (voir `discover`) le temps qu'un `connect`
    /// puisse encore retrouver l'`NWEndpoint` d'un hôte qu'ils ont résolu.
    private var activeBrowses: [(NetServiceBrowser, BrowseDelegate)] = []

    // MARK: - TXT record

    private static func txtRecordData(gameID: String, participantCount: Int, deviceName: String, platform: WireMessage.Platform) -> Data {
        NetService.data(fromTXTRecord: [
            "game": Data(gameID.utf8),
            "players": Data(String(participantCount).utf8),
            "name": Data(deviceName.utf8),
            "platform": Data(platform.rawValue.utf8),
        ])
    }
}

public enum WifiTransportError: Error, Sendable, Equatable {
    case hostNotFound
    case connectionFailed
}

/// Pont vers `NetServiceBrowser`/`NetService` (delegate-based, jamais `Sendable`) : retient les
/// services en cours de résolution (sans quoi ARC les libère avant la fin), et mémorise
/// l'`NWEndpoint` de chaque hôte résolu pour que `WifiTransport.connect(to:)` puisse le retrouver.
private final class BrowseDelegate: NSObject, NetServiceBrowserDelegate, NetServiceDelegate, @unchecked Sendable {
    private var pendingResolutions: [ObjectIdentifier: NetService] = [:]
    private var endpointsByMatchID: [UUID: NWEndpoint] = [:]
    private let onDiscovered: @Sendable (DiscoveredHost) -> Void

    init(onDiscovered: @escaping @Sendable (DiscoveredHost) -> Void) {
        self.onDiscovered = onDiscovered
    }

    func endpoint(for matchID: UUID) -> NWEndpoint? {
        endpointsByMatchID[matchID]
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        pendingResolutions[ObjectIdentifier(service)] = service
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        defer { pendingResolutions[ObjectIdentifier(sender)] = nil }
        guard let matchID = UUID(uuidString: sender.name),
              let hostName = sender.hostName,
              let port = NWEndpoint.Port(rawValue: UInt16(sender.port)),
              let txtData = sender.txtRecordData() else { return }

        let txt = NetService.dictionary(fromTXTRecord: txtData)
        guard let gameID = txt["game"].flatMap({ String(data: $0, encoding: .utf8) }),
              let playersRaw = txt["players"].flatMap({ String(data: $0, encoding: .utf8) }),
              let participantCount = Int(playersRaw),
              let deviceName = txt["name"].flatMap({ String(data: $0, encoding: .utf8) }),
              let platformRaw = txt["platform"].flatMap({ String(data: $0, encoding: .utf8) }),
              let platform = WireMessage.Platform(rawValue: platformRaw) else { return }

        endpointsByMatchID[matchID] = .hostPort(host: .init(hostName), port: port)
        onDiscovered(DiscoveredHost(id: matchID, deviceName: deviceName, gameID: gameID, participantCount: participantCount, platform: platform))
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        pendingResolutions[ObjectIdentifier(sender)] = nil
    }
}

private final class PublishDelegate: NSObject, NetServiceDelegate, @unchecked Sendable {}

/// Fait traverser un type non-`Sendable` (les API `NetService*`, historiques) une fermeture
/// `@Sendable` — valable ici parce que tout `WifiTransport` s'exécute sur `.main`, jamais deux
/// threads concurrents (voir le commentaire d'en-tête du fichier).
private final class UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// Une connexion TCP, tramée par un préfixe de longueur 4 octets (big-endian) : `NWConnection`
/// transporte un flux d'octets, pas des messages — sans ce cadrage, deux `WireMessage` envoyés
/// coup sur coup pourraient être livrés fusionnés ou coupés côté récepteur.
final class WifiTransportSession: TransportSession, @unchecked Sendable {
    private let connection: NWConnection
    private let stream: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation

    init(connection: NWConnection) {
        self.connection = connection
        (stream, continuation) = AsyncStream.makeStream()
        Self.receiveLength(connection: connection, continuation: continuation)
    }

    var incoming: AsyncStream<Data> { stream }

    /// Même défaut que `WifiTransport.advertise` corrige pour le port du listener : sans retirer
    /// le handler après la première résolution, un passage en arrière-plan (ou toute coupure
    /// réseau ultérieure) fait retenter une résolution sur une continuation déjà résolue — crash
    /// systématique au retour au premier plan (bug observé en recette).
    func waitUntilReady() async throws {
        if connection.state == .ready { return }
        try await withCheckedThrowingContinuation { (checked: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [weak connection] state in
                switch state {
                case .ready:
                    connection?.stateUpdateHandler = nil
                    checked.resume()
                case .failed(let error):
                    connection?.stateUpdateHandler = nil
                    checked.resume(throwing: error)
                case .cancelled:
                    connection?.stateUpdateHandler = nil
                    checked.resume(throwing: WifiTransportError.connectionFailed)
                default:
                    break
                }
            }
        }
    }

    func send(_ data: Data) async throws {
        var length = UInt32(data.count).bigEndian
        let framed = Swift.withUnsafeBytes(of: &length) { Data($0) } + data
        try await withCheckedThrowingContinuation { (checked: CheckedContinuation<Void, Error>) in
            connection.send(content: framed, completion: .contentProcessed { error in
                if let error {
                    checked.resume(throwing: error)
                } else {
                    checked.resume()
                }
            })
        }
    }

    func close() async {
        connection.cancel()
        continuation.finish()
    }

    private static func receiveLength(connection: NWConnection, continuation: AsyncStream<Data>.Continuation) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { data, _, isComplete, error in
            guard let data, data.count == 4, error == nil else {
                if isComplete || error != nil { continuation.finish() }
                return
            }
            let length = Int(data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian)
            receivePayload(connection: connection, length: length, continuation: continuation)
        }
    }

    private static func receivePayload(connection: NWConnection, length: Int, continuation: AsyncStream<Data>.Continuation) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, isComplete, error in
            guard let data, error == nil else {
                if isComplete || error != nil { continuation.finish() }
                return
            }
            continuation.yield(data)
            receiveLength(connection: connection, continuation: continuation)
        }
    }
}
