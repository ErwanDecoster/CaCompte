import Foundation
import Observation

/// Doc utilisateur — pont entre les points d'entrée déclenchés hors de tout écran particulier
/// (`.onOpenURL` pour un lien `cacompte://`, `.onContinueUserActivity` pour une reprise Handoff,
/// `perform()` d'un App Intent qui tourne dans le process de l'app via `openAppWhenRun`) et
/// l'onglet « Jeux », qui peut être plusieurs onglets plus loin au moment où l'un ou l'autre
/// arrive. Pas de pattern d'environnement existant dans le projet pour ça (aucun `@Entry`
/// ailleurs) — un unique objet observable partagé, sur le même principe que `AppSettings`.
/// `.shared` (plutôt qu'une instance injectée) est nécessaire pour les App Intents : `perform()`
/// n'a pas accès à l'environnement SwiftUI de la scène.
@MainActor
@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    var pendingJoin: JoinLink.Payload?
    var pendingContinuedMatchID: UUID?
    var pendingGameID: String?
    var wantsResume = false
}
