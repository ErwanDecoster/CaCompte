import ActivityKit
import Domain
import SwiftUI
import WidgetKit

/// Doc utilisateur — Live Activity (roadmap P9) : écran verrouillé + Dynamic Island, mis à jour
/// à chaque manche par `MatchLiveActivityController` (côté app). Tap → même lien que le Widget
/// (`cacompte://resume`, `DeepLinkRouter.wantsResume`).
struct MatchLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MatchActivityAttributes.self) { context in
            MatchLiveActivityLockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.4))
                .widgetURL(URL(string: "cacompte://resume"))
        } dynamicIsland: { context in
            // Doc utilisateur — remontée : le contenu de la région `.bottom` touchait les bords
            // arrondis de l'île, qui le rognaient visuellement. Une marge horizontale (et un peu
            // de haut) est indispensable ici — contrairement à `.leading`/`.trailing`, l'île
            // n'en ajoute pas toute seule pour cette région.
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.gameName, systemImage: context.attributes.gameSymbol)
                        .font(.caption)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Manche \(context.state.roundNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    MatchStandingsRows(standings: context.state.standings)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: context.attributes.gameSymbol)
            } compactTrailing: {
                if let leader = context.state.standings.first {
                    Text(leader.score.formatted())
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
            } minimal: {
                Image(systemName: context.attributes.gameSymbol)
            }
            .widgetURL(URL(string: "cacompte://resume"))
        }
    }
}

private struct MatchLiveActivityLockScreenView: View {
    let context: ActivityViewContext<MatchActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(context.attributes.gameName, systemImage: context.attributes.gameSymbol)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("Manche \(context.state.roundNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            MatchStandingsRows(standings: context.state.standings)
        }
        .padding()
    }
}

private struct MatchStandingsRows: View {
    let standings: [MatchActivityAttributes.ContentState.Standing]

    var body: some View {
        ForEach(standings) { row in
            HStack {
                Text(row.name).lineLimit(1)
                Spacer(minLength: 8)
                Text(row.score.formatted()).fontWeight(.semibold)
            }
            .font(.subheadline)
        }
    }
}
