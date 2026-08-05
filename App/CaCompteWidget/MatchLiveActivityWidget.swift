import ActivityKit
import Domain
import SwiftUI
import WidgetKit

/// Doc utilisateur — Live Activity (roadmap P9) : écran verrouillé + Dynamic Island, mis à jour
/// à chaque manche par `MatchLiveActivityController` (côté app). Tap → même lien que le Widget
/// (`cacompte://resume`, `DeepLinkRouter.wantsResume`). Apple Watch réutilise automatiquement ce
/// même contenu (banner) dans son Smart Stack, sans code séparé — la présentation doit donc
/// rester compacte, l'espace disponible y est plus contraint que sur l'écran verrouillé.
struct MatchLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MatchActivityAttributes.self) { context in
            MatchLiveActivityLockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.4))
                .widgetURL(URL(string: "cacompte://resume"))
        } dynamicIsland: { context in
            // Doc utilisateur — remontée : le contenu de chaque région touchait les bords
            // arrondis de l'île (haut gauche/droite pour leading/trailing, bas pour bottom) —
            // aucune des trois n'a de marge automatique suffisante, contrairement à ce qu'on
            // pourrait croire en ne testant que du texte très court.
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.gameName, systemImage: context.state.gameSymbol)
                        .font(.caption)
                        .lineLimit(1)
                        .padding(.leading, 4)
                        .padding(.top, 2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Manche \(context.state.roundNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                        .padding(.top, 2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        if context.state.isStale {
                            StaleConnectionLabel()
                        }
                        MatchStandingsGrid(standings: context.state.standings)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.gameSymbol)
            } compactTrailing: {
                // Doc utilisateur — remontée : n'affichait que le score du premier joueur, alors
                // que c'est justement l'endroit le plus regardé d'un coup d'œil. `A 12 · B 18`
                // reste lisible en compact pour 2 joueurs (le cas le plus courant) ; au-delà, le
                // reste se trouve dans la vue étendue / l'écran verrouillé.
                Text(compactScoresText(for: context.state.standings))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } minimal: {
                Image(systemName: context.state.gameSymbol)
            }
            .widgetURL(URL(string: "cacompte://resume"))
        }
    }
}

private func compactScoresText(for standings: [MatchActivityAttributes.ContentState.Standing]) -> String {
    standings.prefix(2).map { "\($0.name.prefix(1)) \($0.score)" }.joined(separator: " · ")
}

private struct StaleConnectionLabel: View {
    var body: some View {
        Label("Connexion perdue — dernier score reçu", systemImage: "wifi.slash")
            .font(.caption2)
            .foregroundStyle(.orange)
    }
}

private struct MatchLiveActivityLockScreenView: View {
    let context: ActivityViewContext<MatchActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(context.state.gameName, systemImage: context.state.gameSymbol)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("Manche \(context.state.roundNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if context.state.isStale {
                StaleConnectionLabel()
            }
            MatchStandingsGrid(standings: context.state.standings)
        }
        .padding()
    }
}

/// Doc utilisateur — remontée : en pile verticale, seule la moitié des joueurs tenait dans
/// l'espace réduit du Smart Stack Apple Watch (qui réutilise cette même vue). Une grille à deux
/// colonnes tient sur une seule ligne pour une partie à 2, le cas le plus fréquent, et reste
/// compacte au-delà.
private struct MatchStandingsGrid: View {
    let standings: [MatchActivityAttributes.ContentState.Standing]

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(standings) { row in
                HStack(spacing: 4) {
                    Text(row.name).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(row.score.formatted()).fontWeight(.semibold)
                }
                .font(.subheadline)
            }
        }
    }
}
