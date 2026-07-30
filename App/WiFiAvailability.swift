import Network
import Observation

/// Doc 09 — sans ça, chercher ou annoncer une partie avec le Wi-Fi coupé tourne indéfiniment
/// sans jamais rien trouver, sans dire pourquoi. `NWPathMonitor(requiredInterfaceType: .wifi)`
/// ignore la cellulaire : ce qui compte pour mDNS/DNS-SD, c'est l'interface locale, pas l'accès
/// Internet. Tant que `BLETransport` n'est pas branché dans l'app, le seul conseil possible est
/// d'activer le Wi-Fi — pas encore « sinon on bascule sur Bluetooth ».
@MainActor
@Observable
final class WiFiAvailability {
    private(set) var isAvailable = true

    private let monitor = NWPathMonitor(requiredInterfaceType: .wifi)

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                self?.isAvailable = satisfied
            }
        }
        monitor.start(queue: .main)
    }

    deinit {
        monitor.cancel()
    }
}
