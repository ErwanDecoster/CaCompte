import Observation

/// Doc utilisateur — pont entre `.onOpenURL` (déclenché par l'appareil photo système qui ouvre
/// un lien `cacompte://`, hors de tout écran particulier) et l'écran « Rejoindre une partie »,
/// qui peut être plusieurs onglets plus loin au moment où le lien s'ouvre. Pas de pattern
/// d'environnement existant dans le projet pour ça (aucun `@Entry` ailleurs) — un unique objet
/// observable partagé, sur le même principe que `AppSettings`.
@MainActor
@Observable
final class DeepLinkRouter {
    var pendingJoin: JoinLink.Payload?
}
