import Foundation
import Observation

/// Doc utilisateur — pont entre les points d'entrée déclenchés hors de tout écran particulier
/// (`.onOpenURL` pour un lien `cacompte://`, `.onContinueUserActivity` pour une reprise Handoff)
/// et l'onglet « Jeux », qui peut être plusieurs onglets plus loin au moment où l'un ou l'autre
/// arrive. Pas de pattern d'environnement existant dans le projet pour ça (aucun `@Entry`
/// ailleurs) — un unique objet observable partagé, sur le même principe que `AppSettings`.
@MainActor
@Observable
final class DeepLinkRouter {
    var pendingJoin: JoinLink.Payload?
    var pendingContinuedMatchID: UUID?
}
