import Observation
import UIKit

/// Doc utilisateur — remontée : le bouton de validation persistant (`LiveMatchView`,
/// `SharedMatchView`) ne doit apparaître que quand le clavier est masqué, pour ne pas doublonner
/// le bouton « Suivant » déjà présent dans sa barre d'accessoires. `@FocusState` seul n'est pas
/// fiable pour ça : sur iPad notamment, le bouton natif de fermeture du clavier ne synchronise
/// pas toujours le focus SwiftUI — c'est justement ce qui causait le bug que ce bouton corrige.
@MainActor
@Observable
final class KeyboardObserver {
    private(set) var isVisible = false

    // Doc utilisateur : `@ObservationIgnored` — pas un état d'UI, et `@Observable` génère sinon un
    // accesseur qui entre en conflit avec la lecture depuis `deinit` (jamais isolé à `@MainActor`
    // même pour une classe qui l'est ; sans risque ici, rien d'autre n'accède à `self` à ce moment).
    @ObservationIgnored
    private nonisolated(unsafe) var tokens: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isVisible = true }
        })
        tokens.append(center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isVisible = false }
        })
    }

    deinit {
        let center = NotificationCenter.default
        for token in tokens { center.removeObserver(token) }
    }
}
