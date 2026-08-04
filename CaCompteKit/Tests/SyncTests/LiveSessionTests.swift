import Domain
import Foundation
import Testing
@testable import Sync

/// Comme `EngineInvariantTests` (DomainTests) : un `GameRules` minimal qui n'exerce que les
/// défauts du protocole, pour ne pas faire dépendre `SyncTests` de `Catalog`.
private struct DummyRules: GameRules {
    static let engineID = "test.dummy.v1"
}

private func makeDefinition(max: Int? = nil) -> GameDefinition {
    GameDefinition(
        id: "dummy",
        specVersion: 1,
        rulesVersion: 1,
        name: .init(fr: "Test"),
        symbol: "circle",
        players: .init(min: 2, max: 8),
        scoring: .init(direction: .lowestWins, entry: .init(kind: .integer, max: max)),
        engine: DummyRules.engineID,
        end: .init(conditions: [.init(type: .roundLimit, value: 1000)]),
        tieBreak: [.shared]
    )
}

private func makeCatalog(max: Int? = nil) -> GameCatalog {
    try! GameCatalog(definitions: [makeDefinition(max: max)], engineTable: [DummyRules.engineID: { DummyRules() }])
}

/// Un journal d'une seule manche `matchCreated`, ce que `MatchRepository.createMatch` produirait
/// côté hôte avant de partager la partie (doc 09).
private func makeInitialLog(participants: [Participant]) -> [StampedEvent] {
    [StampedEvent(
        lamport: 0,
        deviceID: "host-device",
        occurredAt: Date(timeIntervalSince1970: 0),
        event: .matchCreated(gameID: "dummy", rulesVersion: 1, variants: VariantSelection(), participants: participants)
    )]
}

/// `AsyncStream` n'a pas de « collecte les N premiers » native — les tests de convergence en ont
/// tous besoin pour attendre que les messages aient fini de traverser les canaux en mémoire.
private func collectFirst<T: Sendable>(_ count: Int, from stream: AsyncStream<T>) async -> [T] {
    var results: [T] = []
    for await item in stream {
        results.append(item)
        if results.count == count { break }
    }
    return results
}

@Suite("LiveSession — hôte autoritaire sur transport en mémoire (doc 09 / ADR-0014)")
struct LiveSessionTests {
    @Test("Une manche proposée par un contributeur est validée, diffusée, et reçue par les deux pairs")
    func contributorProposalConverges() async throws {
        let participants = [Participant(displayName: "Marion", seatIndex: 0), Participant(displayName: "Théo", seatIndex: 1)]
        let catalog = makeCatalog()
        let initialLog = makeInitialLog(participants: participants)
        let sessionID = UUID() // doc 09 « Fin de partie » : indépendant de la partie, fourni par l'appelant

        let host = LiveSession(deviceID: "host-device", catalog: catalog)
        try await host.startHosting(log: initialLog, sessionID: sessionID, pairingCode: "042817")

        let (hostChannel, peerChannel) = InMemoryChannel.pair()
        await host.acceptConnection(hostChannel)

        let peer = LiveSession(deviceID: "peer-device", catalog: catalog)
        try await peer.attachToHost(
            peerChannel,
            sessionID: sessionID,
            pairingCode: "042817",
            requestedRole: .contributor,
            deviceName: "Théo",
            appVersion: "1.0"
        )

        // Le pair reçoit d'abord le `welcome` (le journal initial, un seul événement).
        let welcomeEvents = await collectFirst(1, from: peer.events)
        #expect(welcomeEvents.map(\.event) == [initialLog[0].event])

        let draft = RoundDraft(index: 0, inputs: participants.map { ScoreInput(participantID: $0.id, rawValue: 7) })
        try await peer.propose(.roundCommitted(draft))

        // Sur le pair : l'application optimiste, puis la confirmation de l'hôte (même id, doc 09).
        let peerRoundEvents = await collectFirst(2, from: peer.events)
        #expect(peerRoundEvents.count == 2)
        #expect(peerRoundEvents[0].id == peerRoundEvents[1].id, "la confirmation porte le même id que la proposition optimiste")
        #expect(peerRoundEvents[1].deviceID == "host-device", "l'événement confirmé porte l'horloge de l'hôte, pas celle du pair")

        // Sur l'hôte : l'événement accepté, avant diffusion.
        let hostRoundEvents = await collectFirst(1, from: host.events)
        #expect(hostRoundEvents[0].id == peerRoundEvents[1].id)
        #expect(hostRoundEvents[0].event == .roundCommitted(draft))
    }

    @Test("Un observateur ne peut pas proposer de manche")
    func observerCannotPropose() async throws {
        let participants = [Participant(displayName: "Marion", seatIndex: 0)]
        let catalog = makeCatalog()
        let initialLog = makeInitialLog(participants: participants)
        let sessionID = UUID()

        let host = LiveSession(deviceID: "host-device", catalog: catalog)
        try await host.startHosting(log: initialLog, sessionID: sessionID, pairingCode: "042817")

        let (hostChannel, peerChannel) = InMemoryChannel.pair()
        await host.acceptConnection(hostChannel)

        let observer = LiveSession(deviceID: "observer-device", catalog: catalog)
        try await observer.attachToHost(
            peerChannel,
            sessionID: sessionID,
            pairingCode: "042817",
            requestedRole: .observer,
            deviceName: "David",
            appVersion: "1.0"
        )
        _ = await collectFirst(1, from: observer.events) // laisse le temps au `welcome` d'arriver

        let draft = RoundDraft(index: 0, inputs: [ScoreInput(participantID: participants[0].id, rawValue: 7)])
        await #expect(throws: LiveSession.SessionError.notAuthorized) {
            try await observer.propose(.roundCommitted(draft))
        }
    }

    @Test("L'hôte rejette une manche hors limites et le contributeur en est informé")
    func hostRejectsInvalidRound() async throws {
        let participants = [Participant(displayName: "Marion", seatIndex: 0)]
        let catalog = makeCatalog(max: 10) // doc 04 : `ScoreEntrySpec.max`, vérifié par `validate` par défaut
        let initialLog = makeInitialLog(participants: participants)
        let sessionID = UUID()

        let host = LiveSession(deviceID: "host-device", catalog: catalog)
        try await host.startHosting(log: initialLog, sessionID: sessionID, pairingCode: "042817")

        let (hostChannel, peerChannel) = InMemoryChannel.pair()
        await host.acceptConnection(hostChannel)

        let contributor = LiveSession(deviceID: "peer-device", catalog: catalog)
        try await contributor.attachToHost(
            peerChannel,
            sessionID: sessionID,
            pairingCode: "042817",
            requestedRole: .contributor,
            deviceName: "Théo",
            appVersion: "1.0"
        )
        _ = await collectFirst(1, from: contributor.events) // welcome

        let tooHigh = RoundDraft(index: 0, inputs: [ScoreInput(participantID: participants[0].id, rawValue: 999)])
        try await contributor.propose(.roundCommitted(tooHigh))

        let rejections = await collectFirst(1, from: contributor.rejections)
        #expect(rejections.count == 1)
    }

    @Test("L'hôte peut changer de partie sans rompre la connexion d'un pair, ni changer la clé de chiffrement")
    func switchMatchKeepsConnectionAndKey() async throws {
        let participantsA = [Participant(displayName: "Marion", seatIndex: 0), Participant(displayName: "Théo", seatIndex: 1)]
        let catalog = makeCatalog()
        let initialLogA = makeInitialLog(participants: participantsA)
        let sessionID = UUID()

        let host = LiveSession(deviceID: "host-device", catalog: catalog)
        try await host.startHosting(log: initialLogA, sessionID: sessionID, pairingCode: "042817")

        let (hostChannel, peerChannel) = InMemoryChannel.pair()
        await host.acceptConnection(hostChannel)

        let peer = LiveSession(deviceID: "peer-device", catalog: catalog)
        try await peer.attachToHost(
            peerChannel,
            sessionID: sessionID,
            pairingCode: "042817",
            requestedRole: .contributor,
            deviceName: "Théo",
            appVersion: "1.0"
        )
        _ = await collectFirst(1, from: peer.events) // welcome de la partie A

        // Doc 09 « Fin de partie » — l'hôte enchaîne une nouvelle partie (jeu rejoué ou différent)
        // sans jamais rouvrir la connexion ni le canal : même `sessionID`, même code, mêmes pairs.
        let participantsB = [Participant(displayName: "Marion", seatIndex: 0), Participant(displayName: "Théo", seatIndex: 1)]
        let initialLogB = makeInitialLog(participants: participantsB)
        try await host.switchMatch(log: initialLogB)

        // Le pair reçoit le nouveau journal via `matchChanged`, pas `events` (qui ne porte que les
        // propositions distantes acceptées).
        let changedLogs = await collectFirst(1, from: peer.matchChanged)
        #expect(changedLogs.first?.map(\.event) == initialLogB.map(\.event))

        // La clé de chiffrement n'a pas changé : le pair peut continuer à proposer des manches sur
        // la nouvelle partie sans se réappairer.
        let draft = RoundDraft(index: 0, inputs: participantsB.map { ScoreInput(participantID: $0.id, rawValue: 5) })
        try await peer.propose(.roundCommitted(draft))

        let hostRoundEvents = await collectFirst(1, from: host.events)
        #expect(hostRoundEvents[0].event == .roundCommitted(draft))
    }
}
