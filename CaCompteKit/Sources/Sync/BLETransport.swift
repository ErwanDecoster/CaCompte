import CoreBluetooth
import Foundation

/// Doc 09 / ADR-0014 — secours quand aucun Wi-Fi commun n'est trouvé : Bluetooth Low Energy, un
/// standard cross-vendor (Bluetooth SIG), sans aucune infrastructure réseau requise. Mêmes rôles
/// que `WifiTransport` : l'hôte est le périphérique GATT (`CBPeripheralManager`, annonce et sert
/// les données), qui rejoint est le central (`CBCentralManager`, scanne et se connecte).
///
/// **Non vérifié par exécution**, contrairement à `WifiTransport`. Le Bluetooth ne se prête pas
/// à l'auto-test en self-communication sur une seule machine (essayé : l'autorisation système
/// est accordée des deux côtés, mais la découverte locale n'aboutit jamais — vraisemblablement
/// une limite du framework en self-discovery, pas un bug de code) ; le simulateur iOS n'a de
/// toute façon aucun support Bluetooth. La recette se fait sur deux appareils physiques.
/// Pas encore branché dans l'app (`ShareSessionView`/`JoinMatchView` n'utilisent que
/// `WifiTransport`) : l'orchestration Wi-Fi-puis-BLE de la doc 09 reste à écrire une fois ce
/// transport validé.
///
/// **Découverte : contrainte spécifique au BLE.** Un paquet d'annonce ne peut pas porter
/// `gameID`/`participantCount`/`deviceName` (31 octets au total, déjà presque entièrement pris
/// par un UUID de service 128 bits) — contrairement au TXT record mDNS du Wi-Fi. La découverte
/// se fait donc en deux temps : l'annonce ne porte que l'UUID de service, puis chaque
/// périphérique trouvé est connecté brièvement pour lire une caractéristique d'info (JSON, les
/// mêmes champs que `DiscoveredHost`), avant d'être déconnecté si l'utilisateur ne le choisit
/// pas. `connect(to:)` se reconnecte ensuite proprement, sans réutiliser cette connexion de
/// lecture.
public final class BLETransport: NSObject, Transport, @unchecked Sendable {
    // `CBUUID` n'est pas `Sendable` (API historique) ; ces constantes ne sont jamais réassignées
    // après leur initialisation au chargement du programme, `nonisolated(unsafe)` est donc sûr.
    nonisolated(unsafe) static let serviceUUID = CBUUID(string: "515FCEDB-1A0E-442A-A323-CF7E31FC5290")
    nonisolated(unsafe) static let infoCharUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    nonisolated(unsafe) static let writeCharUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    nonisolated(unsafe) static let notifyCharUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    private let deviceName: String
    private let platform: WireMessage.Platform

    private var peripheralDelegate: BLEPeripheralDelegate?
    private var centralDelegate: BLECentralDelegate?

    private let acceptedStream: AsyncStream<any TransportSession>
    private let acceptedContinuation: AsyncStream<any TransportSession>.Continuation

    public init(deviceName: String, platform: WireMessage.Platform = .apple) {
        self.deviceName = deviceName
        self.platform = platform
        (acceptedStream, acceptedContinuation) = AsyncStream.makeStream()
        super.init()
    }

    public func advertise(matchID: UUID, gameID: String, participantCount: Int) async throws {
        let info = BLEHostInfo(matchID: matchID, gameID: gameID, participantCount: participantCount, deviceName: deviceName, platform: platform)
        let infoData = try JSONEncoder().encode(info)
        let delegate = BLEPeripheralDelegate(infoData: infoData) { [acceptedContinuation] session in
            acceptedContinuation.yield(session)
        }
        peripheralDelegate = delegate
        try await delegate.startAdvertising()
    }

    public func stopAdvertising() async {
        peripheralDelegate?.stop()
        peripheralDelegate = nil
    }

    public func acceptIncoming() -> AsyncStream<any TransportSession> {
        acceptedStream
    }

    /// Doc utilisateur P9 — remontée (« Se reconnecter » restait bloqué en chargement) : une
    /// nouvelle instance de `BLECentralDelegate` à chaque appel voulait dire un nouveau
    /// `CBCentralManager` à chaque fois — Apple documente explicitement qu'une seule instance par
    /// app est le fonctionnement supporté, en créer plusieurs produit un comportement non garanti
    /// (état `.poweredOn` qui n'arrive jamais, scan qui ne démarre pas). `reconnect()` et
    /// `beginBLEHandoverIfNeeded` (`JoinMatchView`) sont les premiers appelants à redécouvrir
    /// plusieurs fois sur le même `BLETransport` — jusqu'ici chaque tentative de rejoindre
    /// repartait d'un `BLETransport` fraîchement créé, ce bug restait invisible.
    public func discover(timeout: Duration) -> AsyncStream<DiscoveredHost> {
        let delegate = centralDelegate ?? BLECentralDelegate()
        centralDelegate = delegate
        return delegate.discover(timeout: timeout)
    }

    public func connect(to host: DiscoveredHost) async throws -> any TransportSession {
        guard let centralDelegate else { throw BLETransportError.notDiscovering }
        return try await centralDelegate.connect(to: host)
    }
}

public enum BLETransportError: Error, Sendable, Equatable {
    case notDiscovering
    case hostNotFound
    case connectionFailed
    case bluetoothUnavailable
}

struct BLEHostInfo: Codable {
    let matchID: UUID
    let gameID: String
    let participantCount: Int
    let deviceName: String
    let platform: WireMessage.Platform
}

/// Cadrage commun aux deux sens : un préfixe de longueur 4 octets (big-endian), comme
/// `WifiTransportSession`, mais découpé en morceaux de la taille d'une écriture de
/// caractéristique — une caractéristique BLE ne transporte jamais un flux continu.
enum BLEFraming {
    static let chunkSize = 180

    static func frame(_ data: Data) -> [Data] {
        var length = UInt32(data.count).bigEndian
        let framed = withUnsafeBytes(of: &length) { Data($0) } + data
        return stride(from: 0, to: framed.count, by: chunkSize).map { start in
            framed.subdata(in: start..<Swift.min(start + chunkSize, framed.count))
        }
    }

    /// Retire et retourne un message complet du tampon dès qu'il y en a un — appelé après
    /// chaque morceau reçu, peut en extraire zéro, un ou plusieurs si plusieurs messages courts
    /// sont arrivés d'un coup.
    static func extractMessage(from buffer: inout Data) -> Data? {
        guard buffer.count >= 4 else { return nil }
        let length = Int(buffer.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian)
        guard buffer.count >= 4 + length else { return nil }
        let message = buffer.subdata(in: 4..<(4 + length))
        buffer.removeSubrange(0..<(4 + length))
        return message
    }
}

// MARK: - Hôte (périphérique GATT)

/// Un seul rôle : servir la caractéristique d'info (valeur statique, lue automatiquement par
/// CoreBluetooth sans passer par le délégué) et relayer les écritures/notifications vers/depuis
/// chaque central connecté, une `BLEPeripheralSession` par central.
final class BLEPeripheralDelegate: NSObject, CBPeripheralManagerDelegate, @unchecked Sendable {
    private var manager: CBPeripheralManager!
    private let infoData: Data
    private let onSessionAccepted: @Sendable (any TransportSession) -> Void
    private var notifyChar: CBMutableCharacteristic!
    private var sessionsByCentral: [ObjectIdentifier: BLEPeripheralSession] = [:]
    private var readyContinuation: CheckedContinuation<Void, Error>?

    init(infoData: Data, onSessionAccepted: @escaping @Sendable (any TransportSession) -> Void) {
        self.infoData = infoData
        self.onSessionAccepted = onSessionAccepted
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: .main)
    }

    func startAdvertising() async throws {
        switch manager.state {
        case .unsupported, .unauthorized:
            throw BLETransportError.bluetoothUnavailable
        case .poweredOn:
            setUpServiceAndAdvertise()
            return
        default:
            break // .poweredOff / .unknown / .resetting : on attend l'état suivant
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            readyContinuation = continuation
        }
    }

    func stop() {
        manager.stopAdvertising()
        manager.removeAllServices()
        for session in sessionsByCentral.values { session.markClosed() }
        sessionsByCentral = [:]
    }

    private func setUpServiceAndAdvertise() {
        let infoChar = CBMutableCharacteristic(type: BLETransport.infoCharUUID, properties: [.read], value: infoData, permissions: [.readable])
        let writeChar = CBMutableCharacteristic(type: BLETransport.writeCharUUID, properties: [.write], value: nil, permissions: [.writeable])
        let notify = CBMutableCharacteristic(type: BLETransport.notifyCharUUID, properties: [.notify], value: nil, permissions: [])
        notifyChar = notify
        let service = CBMutableService(type: BLETransport.serviceUUID, primary: true)
        service.characteristics = [infoChar, writeChar, notify]
        manager.add(service)
        manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [BLETransport.serviceUUID]])
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard let continuation = readyContinuation else { return }
        switch peripheral.state {
        case .poweredOn:
            readyContinuation = nil
            setUpServiceAndAdvertise()
            continuation.resume()
        case .unsupported, .unauthorized:
            readyContinuation = nil
            continuation.resume(throwing: BLETransportError.bluetoothUnavailable)
        default:
            break
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard request.characteristic.uuid == BLETransport.writeCharUUID, let value = request.value else { continue }
            session(for: request.central).receiveChunk(value)
            peripheral.respond(to: request, withResult: .success)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard characteristic.uuid == BLETransport.notifyCharUUID else { return }
        onSessionAccepted(session(for: central))
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        let key = ObjectIdentifier(central)
        sessionsByCentral[key]?.markClosed()
        sessionsByCentral[key] = nil
    }

    private func session(for central: CBCentral) -> BLEPeripheralSession {
        let key = ObjectIdentifier(central)
        if let existing = sessionsByCentral[key] { return existing }
        let session = BLEPeripheralSession(central: central, manager: manager, notifyChar: notifyChar)
        sessionsByCentral[key] = session
        return session
    }
}

/// Le sens hôte → pair (notifications) doit composer avec la file d'attente de
/// `CBPeripheralManager` : `updateValue` retourne `false` si elle est pleine, sans autre recours
/// que réessayer plus tard. Une pause fixe plutôt qu'un réveil sur `peripheralManagerIsReady`
/// évite une course entre le thread qui pose la continuation et la queue `.main` qui la
/// résoudrait — plus simple à garantir correct qu'à optimiser, faute de pouvoir vérifier ce
/// chemin sur un vrai appareil ici.
final class BLEPeripheralSession: TransportSession, @unchecked Sendable {
    private let central: CBCentral
    private weak var manager: CBPeripheralManager?
    private let notifyChar: CBMutableCharacteristic
    private let stream: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private var incomingBuffer = Data()

    init(central: CBCentral, manager: CBPeripheralManager, notifyChar: CBMutableCharacteristic) {
        self.central = central
        self.manager = manager
        self.notifyChar = notifyChar
        (stream, continuation) = AsyncStream.makeStream()
    }

    var incoming: AsyncStream<Data> { stream }

    func receiveChunk(_ chunk: Data) {
        incomingBuffer.append(chunk)
        while let message = BLEFraming.extractMessage(from: &incomingBuffer) {
            continuation.yield(message)
        }
    }

    /// Doc utilisateur P9 — remontée (une manche sur deux n'arrivait jamais côté pair en
    /// arrière-plan) : sans limite, une notification qu'aucun central n'écoute plus vraiment
    /// (lien BLE mort côté pair, mais `didUnsubscribeFrom` pas encore reçu — la supervision BLE
    /// peut prendre bien plus longtemps qu'un `updateValue` à réessayer) bloquait cette boucle
    /// indéfiniment, silencieusement : `syncSharedLogIfNeeded` (hôte) restait bloqué pour de bon
    /// sur cette manche, sans jamais échouer ni réessayer la suivante. Une limite fait échouer
    /// proprement plutôt que de rester bloqué sans fin.
    private static let maxUpdateAttempts = 250 // ~5 s à 20 ms/tentative

    func send(_ data: Data) async throws {
        guard let manager else { throw BLETransportError.connectionFailed }
        for chunk in BLEFraming.frame(data) {
            var attempts = 0
            while !manager.updateValue(chunk, for: notifyChar, onSubscribedCentrals: [central]) {
                attempts += 1
                guard attempts < Self.maxUpdateAttempts else { throw BLETransportError.connectionFailed }
                try await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    func markClosed() {
        continuation.finish()
    }

    /// `CBPeripheralManager` n'offre aucun moyen de couper la connexion d'un central précis —
    /// seul le central peut se déconnecter lui-même. Au mieux, on arrête d'écouter localement ;
    /// documenté comme limite de plateforme, pas comme bug, dans doc 09.
    func close() async {
        continuation.finish()
    }
}

// MARK: - Pair qui rejoint (central)

final class BLECentralDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    private static let connectTimeout: Duration = .seconds(10)

    private var manager: CBCentralManager!
    private var peripheralsByMatchID: [UUID: CBPeripheral] = [:]
    private var peekingPeripherals: Set<ObjectIdentifier> = []
    private var discoveryContinuation: AsyncStream<DiscoveredHost>.Continuation?
    private var activeSession: BLECentralSession?
    private var connectContinuation: CheckedContinuation<any TransportSession, Error>?

    override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: .main)
    }

    func discover(timeout: Duration) -> AsyncStream<DiscoveredHost> {
        AsyncStream { continuation in
            discoveryContinuation = continuation
            if manager.state == .poweredOn {
                manager.scanForPeripherals(withServices: [BLETransport.serviceUUID])
            }
            let task = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.manager.stopScan()
                continuation.finish()
            }
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                self?.manager.stopScan()
            }
        }
    }

    func connect(to host: DiscoveredHost) async throws -> any TransportSession {
        guard let peripheral = peripheralsByMatchID[host.id] else {
            throw BLETransportError.hostNotFound
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<any TransportSession, Error>) in
            connectContinuation = continuation
            peripheral.delegate = self
            manager.connect(peripheral)
            Task { [weak self] in
                try? await Task.sleep(for: Self.connectTimeout)
                guard let self, let pending = self.connectContinuation else { return }
                self.connectContinuation = nil
                pending.resume(throwing: BLETransportError.connectionFailed)
            }
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn, discoveryContinuation != nil else { return }
        central.scanForPeripherals(withServices: [BLETransport.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let key = ObjectIdentifier(peripheral)
        guard !peekingPeripherals.contains(key) else { return }
        guard !peripheralsByMatchID.values.contains(where: { $0.identifier == peripheral.identifier }) else { return }
        peekingPeripherals.insert(key)
        peripheral.delegate = self
        manager.connect(peripheral) // connexion brève, juste pour lire la caractéristique d'info
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([BLETransport.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        peekingPeripherals.remove(ObjectIdentifier(peripheral))
        failPendingConnect(for: peripheral, error: BLETransportError.connectionFailed)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        peekingPeripherals.remove(ObjectIdentifier(peripheral))
        if activeSession?.matches(peripheral) == true {
            activeSession?.markClosed()
            activeSession = nil
        }
        failPendingConnect(for: peripheral, error: BLETransportError.connectionFailed)
    }

    private func failPendingConnect(for peripheral: CBPeripheral, error: Error) {
        guard let pending = connectContinuation else { return }
        connectContinuation = nil
        pending.resume(throwing: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == BLETransport.serviceUUID }) else { return }
        if peekingPeripherals.contains(ObjectIdentifier(peripheral)) {
            peripheral.discoverCharacteristics([BLETransport.infoCharUUID], for: service)
        } else {
            peripheral.discoverCharacteristics([BLETransport.writeCharUUID, BLETransport.notifyCharUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        if peekingPeripherals.contains(ObjectIdentifier(peripheral)) {
            guard let infoChar = characteristics.first(where: { $0.uuid == BLETransport.infoCharUUID }) else { return }
            peripheral.readValue(for: infoChar)
            return
        }
        guard let writeChar = characteristics.first(where: { $0.uuid == BLETransport.writeCharUUID }) else { return }
        if let notifyChar = characteristics.first(where: { $0.uuid == BLETransport.notifyCharUUID }) {
            peripheral.setNotifyValue(true, for: notifyChar)
        }
        let session = BLECentralSession(peripheral: peripheral, writeChar: writeChar)
        activeSession = session
        connectContinuation?.resume(returning: session)
        connectContinuation = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value else { return }
        if characteristic.uuid == BLETransport.infoCharUUID {
            guard let info = try? JSONDecoder().decode(BLEHostInfo.self, from: value) else { return }
            peripheralsByMatchID[info.matchID] = peripheral
            peekingPeripherals.remove(ObjectIdentifier(peripheral))
            discoveryContinuation?.yield(DiscoveredHost(id: info.matchID, deviceName: info.deviceName, gameID: info.gameID, participantCount: info.participantCount, platform: info.platform))
            manager.cancelPeripheralConnection(peripheral) // lecture seule : `connect(to:)` reconnectera pour de bon
        } else if characteristic.uuid == BLETransport.notifyCharUUID {
            activeSession?.receiveChunk(value)
        }
    }
}

final class BLECentralSession: TransportSession, @unchecked Sendable {
    let peripheral: CBPeripheral
    private let writeChar: CBCharacteristic
    private let stream: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private var incomingBuffer = Data()

    init(peripheral: CBPeripheral, writeChar: CBCharacteristic) {
        self.peripheral = peripheral
        self.writeChar = writeChar
        (stream, continuation) = AsyncStream.makeStream()
    }

    var incoming: AsyncStream<Data> { stream }

    func matches(_ candidate: CBPeripheral) -> Bool {
        candidate.identifier == peripheral.identifier
    }

    func receiveChunk(_ chunk: Data) {
        incomingBuffer.append(chunk)
        while let message = BLEFraming.extractMessage(from: &incomingBuffer) {
            continuation.yield(message)
        }
    }

    /// Écritures `.withResponse` envoyées à la suite, sans attendre la confirmation de chaque
    /// morceau : CoreBluetooth les sérialise et les acquitte dans l'ordre pour un même lien —
    /// attendre `didWriteValueFor` entre chaque morceau ajouterait de la latence sans changer la
    /// garantie d'ordre, déjà assurée par GATT sur une connexion unique.
    func send(_ data: Data) async throws {
        for chunk in BLEFraming.frame(data) {
            peripheral.writeValue(chunk, for: writeChar, type: .withResponse)
        }
    }

    func markClosed() {
        continuation.finish()
    }

    func close() async {
        continuation.finish()
    }
}
