import ActivityKit
import Domain
import Foundation

/// Doc utilisateur — Live Activity (roadmap P9) : point d'entrée unique pour les trois écrans de
/// saisie (`LiveMatchModel`, `YamsSheetModel`, `BeloteRoundModel`), qui partagent tous la même
/// forme `state`/`definition`/`rules` (doc « point d'aiguillage unique », `MatchPlayView`). Un
/// dictionnaire par id de partie plutôt qu'un singleton simple : rien n'empêche en théorie deux
/// parties d'être à l'écran l'une après l'autre dans la même session.
@MainActor
enum MatchLiveActivityController {
    private static var activities: [UUID: Activity<MatchActivityAttributes>] = [:]

    static func refresh(definition: GameDefinition, rules: any GameRules, state: MatchState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let names = Dictionary(uniqueKeysWithValues: state.participants.map { ($0.id, $0.displayName) })
        let standings = rules.standings(state, definition: definition)
            .sorted { $0.rank < $1.rank }
            .prefix(4)
            .map { MatchActivityAttributes.ContentState.Standing(id: $0.participantID, name: names[$0.participantID] ?? "", score: $0.score) }
        let content = MatchActivityAttributes.ContentState(roundNumber: state.rounds.count, standings: Array(standings))
        let hasEnded = state.status == .ended || state.status == .abandoned
        let matchID = state.matchID
        let attributes = MatchActivityAttributes(matchID: matchID, gameName: definition.name.fr, gameSymbol: definition.symbol)

        // Doc utilisateur — tout le travail (y compris la lecture/écriture d'`activities`) se
        // fait à l'intérieur de cette tâche : `Activity` n'est pas `Sendable` côté SDK, donc le
        // capturer depuis l'extérieur pour l'utiliser ici violerait la vérification « sending »
        // de Swift 6. `activities` reste protégé par `@MainActor`, pas par cette tâche elle-même.
        Task { @MainActor in
            // Doc utilisateur : `Activity` (ActivityKit) n'est pas `Sendable` côté SDK alors que
            // `update`/`end` sont `nonisolated async` — `nonisolated(unsafe)` est l'échappatoire
            // documentée pour ce décalage précis, pas un contournement maison.
            if hasEnded {
                // Doc utilisateur — remontée : `.default` gardait la carte affichée un moment
                // après la fin de partie (comportement voulu au départ, « voir le score final »),
                // mais ça se lisait comme un bug (« la partie est finie, pourquoi c'est encore
                // là ? »). Retrait immédiat, comme `stopTracking` ci-dessous.
                guard let found = activities.removeValue(forKey: matchID) else { return }
                nonisolated(unsafe) let activity = found
                await activity.end(ActivityContent(state: content, staleDate: nil), dismissalPolicy: .immediate)
                return
            }

            if let found = activities[matchID] {
                nonisolated(unsafe) let activity = found
                await activity.update(ActivityContent(state: content, staleDate: nil))
            } else {
                // Doc utilisateur : `Activity.request` échoue si les Live Activities sont
                // refusées dans les réglages système, ou si le budget d'activités simultanées
                // est épuisé — la partie reste jouable sans, seul l'écran verrouillé n'affiche
                // rien de plus.
                activities[matchID] = try? Activity.request(attributes: attributes, content: ActivityContent(state: content, staleDate: nil))
            }
        }
    }

    /// Doc utilisateur — un pair qui quitte une partie partagée sans qu'elle soit terminée (P9,
    /// remontée utilisateur) : retrait immédiat, même logique que la fin de partie ci-dessus.
    static func stopTracking(matchID: UUID) {
        Task { @MainActor in
            guard let found = activities.removeValue(forKey: matchID) else { return }
            nonisolated(unsafe) let activity = found
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Doc utilisateur — remontée : une connexion perdue côté pair (hôte arrêté, coupure réseau
    /// prolongée) sans rien faire laissait l'écran verrouillé afficher le dernier score reçu comme
    /// s'il était toujours en direct.
    /// Republie le même contenu marqué `isStale`, plutôt que de le deviner depuis `staleDate` seul
    /// (peu visible pour du contenu statique) — `refresh` efface le marqueur de lui-même dès que
    /// de nouveaux événements arrivent (reconnexion réussie).
    static func markStale(matchID: UUID) {
        Task { @MainActor in
            guard let found = activities[matchID] else { return }
            nonisolated(unsafe) let activity = found
            let current = activity.content.state
            guard !current.isStale else { return }
            let staleContent = MatchActivityAttributes.ContentState(
                roundNumber: current.roundNumber,
                standings: current.standings,
                isStale: true
            )
            await activity.update(ActivityContent(state: staleContent, staleDate: .now))
        }
    }
}
