import Catalog
import Domain
import Store
import SwiftData
import SwiftUI
import WidgetKit

struct MatchSnapshot {
    let gameName: String
    let gameSymbol: String
    let roundNumber: Int
    let standings: [(name: String, score: Int)]
}

struct MatchWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: MatchSnapshot?
}

/// Doc utilisateur — Widget (roadmap P9) : lit le store SwiftData partagé via App Group
/// (`SharedStore`, doc 03) sans jamais y écrire — seule l'app pilote la synchronisation
/// CloudKit. `policy: .never`-like (`.after` très éloigné) : un score ne change que sur action
/// explicite d'un joueur, jamais en continu — c'est l'app qui republie la timeline
/// (`WidgetCenter.reloadAllTimelines`, `CaCompteApp`) au moment le plus probable où
/// l'utilisateur va la consulter, quand elle repasse en arrière-plan.
struct MatchTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> MatchWidgetEntry {
        MatchWidgetEntry(date: .now, snapshot: MatchSnapshot(
            gameName: "Skyjo",
            gameSymbol: "die.face.5",
            roundNumber: 3,
            standings: [(name: "Alice", score: 12), (name: "Bob", score: 18)]
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (MatchWidgetEntry) -> Void) {
        completion(MatchWidgetEntry(date: .now, snapshot: Self.currentSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MatchWidgetEntry>) -> Void) {
        let entry = MatchWidgetEntry(date: .now, snapshot: Self.currentSnapshot())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
    }

    /// Doc utilisateur — lit directement le `ModelContext` plutôt que de passer par
    /// `MatchRepository` (`@MainActor`, doc 02 : pensé pour les écritures interactives) : un
    /// `TimelineProvider` n'a aucune garantie d'être appelé sur le thread principal, et cette
    /// lecture seule n'a pas besoin de cette contrainte.
    private static func currentSnapshot() -> MatchSnapshot? {
        guard let url = SharedStore.storeURL else { return nil }
        let schema = Schema(CaCompteSchemaV1.models)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        guard let container = try? ModelContainer(for: schema, configurations: [configuration]) else { return nil }

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<MatchRecord>(
            predicate: #Predicate { $0.statusRaw == "inProgress" || $0.statusRaw == "finalRound" }
        )
        guard let match = try? context.fetch(descriptor).first else { return nil }

        let catalog = GameCatalog.embedded
        guard let definition = try? catalog.definition(for: match.gameID, version: match.rulesVersion),
              let rules = try? catalog.rules(for: match.gameID, version: match.rulesVersion),
              let events = try? JSONDecoder().decode([StampedEvent].self, from: match.eventLogData),
              let state = try? MatchEngine().replay(events, catalog: catalog) else { return nil }

        let names = Dictionary(uniqueKeysWithValues: state.participants.map { ($0.id, $0.displayName) })
        let standings = rules.standings(state, definition: definition)
            .sorted { $0.rank < $1.rank }
            .prefix(4)
            .map { (name: names[$0.participantID] ?? "", score: $0.score) }

        return MatchSnapshot(
            gameName: definition.name.fr,
            gameSymbol: definition.symbol,
            roundNumber: state.rounds.count + 1,
            standings: Array(standings)
        )
    }
}

struct MatchWidgetEntryView: View {
    var entry: MatchWidgetEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 6) {
                Label(snapshot.gameName, systemImage: snapshot.gameSymbol)
                    .font(.headline)
                    .lineLimit(1)
                Text("Manche \(snapshot.roundNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(snapshot.standings.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(row.name).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(row.score.formatted()).fontWeight(.semibold)
                    }
                    .font(.subheadline)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(URL(string: "cacompte://resume"))
        } else {
            VStack(spacing: 6) {
                Image(systemName: "die.face.5.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Aucune partie en cours")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetURL(URL(string: "cacompte://"))
        }
    }
}

struct MatchWidget: Widget {
    let kind = "MatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MatchTimelineProvider()) { entry in
            MatchWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Partie en cours")
        .description("Le classement de la partie en cours, en un coup d'œil.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
