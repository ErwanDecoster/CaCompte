import Foundation
import Store

/// Doc utilisateur — Handoff (roadmap P9) : reprendre la saisie d'une partie en cours sur un
/// autre appareil connecté au même compte iCloud. Contrairement à `JoinLink` (partie partagée en
/// temps réel, doc 09), un seul appareil saisit à la fois — l'activité ne transporte donc que
/// l'id de la partie, résolue depuis le store local une fois reçue côté destinataire (déjà
/// synchronisé via CloudKit, doc 03 ; sinon la reprise échoue silencieusement, comme un lien de
/// partie qui n'existe plus).
enum MatchContinuation {
    static let activityType = "com.cacompte.app.continueMatch"
    private static let matchIDKey = "matchID"

    static func configure(_ activity: NSUserActivity, for match: MatchRecord, gameName: String?) {
        activity.title = gameName.map { "Partie de \($0)" } ?? "Continuer la partie"
        activity.userInfo = [matchIDKey: match.id.uuidString]
        activity.isEligibleForHandoff = true
    }

    static func matchID(from activity: NSUserActivity) -> UUID? {
        guard activity.activityType == activityType,
              let raw = activity.userInfo?[matchIDKey] as? String else { return nil }
        return UUID(uuidString: raw)
    }
}
