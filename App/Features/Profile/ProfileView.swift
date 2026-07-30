import Catalog
import Charts
import DesignSystem
import Domain
import Store
import SwiftData
import SwiftUI

/// Doc 06 « Statistiques de profil » — agrégées sur tout l'historique, calculées à la demande
/// (aucune valeur mise en cache/persistée : « un agrégat stocké est un agrégat qui finira
/// désynchronisé »).
struct ProfileView: View {
    let player: PlayerRecord

    @Environment(\.modelContext) private var modelContext
    @State private var stats: ProfileStats = .empty
    @State private var isPresentingEditor = false
    /// Doc utilisateur — le mois en cours par défaut, l'année en un tap : `stats.activity`
    /// couvre déjà 12 mois (doc 06), rien à recalculer, seule la présentation change.
    @State private var isShowingFullYear = false

    private var catalog: GameCatalog { .embedded }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                header
                if stats.played == 0 {
                    EmptyState(
                        icon: "chart.bar.doc.horizontal",
                        message: "Aucune partie terminée pour l'instant. La fiche se remplit après la première partie."
                    )
                } else {
                    summarySection
                    if !stats.byGame.isEmpty {
                        byGameSection
                    }
                    if let nemesis = stats.nemesis {
                        nemesisSection(nemesis)
                    }
                    streaksSection
                    if stats.activity.contains(where: { $0.count > 0 }) {
                        activitySection
                    }
                }
            }
            .padding(Space.lg)
        }
        .background(.neutralBg)
        .navigationTitle(player.nickname)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Modifier", systemImage: "pencil") {
                    isPresentingEditor = true
                }
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            PlayerEditorView(mode: .edit(player), context: modelContext)
        }
        .task(id: player.id) { load() }
    }

    private func load() {
        stats = (try? ProfileRepository(context: modelContext).stats(for: player, catalog: catalog)) ?? .empty
    }

    private var header: some View {
        HStack(spacing: Space.md) {
            AvatarView(avatar: player.avatar, size: .large)
            Text(player.nickname).font(.h2).foregroundStyle(.textPrimary)
            Spacer(minLength: 0)
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("En bref").font(.h4).foregroundStyle(.textPrimary)
            Card {
                HStack {
                    statBlock(value: "\(stats.played)", label: "Parties")
                    Spacer()
                    statBlock(value: "\(stats.wins)", label: "Victoires")
                    Spacer()
                    statBlock(value: stats.winRate.formatted(.percent.precision(.fractionLength(0))), label: "Taux de victoire")
                    Spacer()
                    statBlock(value: String(format: "%.1f", stats.averageRank), label: "Rang moyen")
                }
            }
        }
    }

    private func statBlock(value: String, label: LocalizedStringResource) -> some View {
        VStack(spacing: Space.xxs) {
            Text(value).font(.h4).foregroundStyle(.textPrimary)
            Text(label).font(.label).foregroundStyle(.textSecondary)
        }
    }

    private var byGameSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Par jeu").font(.h4).foregroundStyle(.textPrimary)
            ForEach(stats.byGame, id: \.gameID) { game in
                Card {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(game.gameName).font(.h6).foregroundStyle(.textPrimary)
                        Text("\(game.played) partie(s) · \(game.wins) victoire(s) · \(game.winRate.formatted(.percent.precision(.fractionLength(0))))")
                            .font(.bodySmall)
                            .foregroundStyle(.textSecondary)
                        if let best = game.bestScore {
                            Text("Meilleur score : \(best.value) — \(best.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.bodySmall)
                                .foregroundStyle(.textSecondary)
                        }
                        if let worst = game.worstScore {
                            Text("Pire score : \(worst.value) — \(worst.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.bodySmall)
                                .foregroundStyle(.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private func nemesisSection(_ nemesis: ProfileStats.Nemesis) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Némésis").font(.h4).foregroundStyle(.textPrimary)
            Card {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(nemesis.name).font(.h6).foregroundStyle(.textPrimary)
                    Text("\(nemesis.matchesTogether) partie(s) ensemble · \(nemesis.winRateWithThemPresent.formatted(.percent.precision(.fractionLength(0)))) de victoires")
                        .font(.bodySmall)
                        .foregroundStyle(.textSecondary)
                }
            }
        }
    }

    private var streaksSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Séries").font(.h4).foregroundStyle(.textPrimary)
            Card {
                HStack {
                    statBlock(value: "\(stats.currentWinStreak)", label: "Série en cours")
                    Spacer()
                    statBlock(value: "\(stats.bestWinStreak)", label: "Record")
                }
            }
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Text("Activité").font(.h4).foregroundStyle(.textPrimary)
                Spacer()
                Button(isShowingFullYear ? "Voir le mois" : "Voir l'année") {
                    withAnimation { isShowingFullYear.toggle() }
                }
                .font(.label)
            }
            Card {
                if isShowingFullYear {
                    Chart(stats.activity) { month in
                        BarMark(
                            x: .value("Mois", monthLabel(month.monthKey)),
                            y: .value("Parties", month.count)
                        )
                        .foregroundStyle(.brandInk)
                    }
                    .frame(height: 140)
                } else {
                    HStack {
                        statBlock(value: "\(currentMonthActivity)", label: "Parties ce mois-ci")
                        Spacer()
                    }
                }
            }
        }
    }

    private var currentMonthActivity: Int {
        stats.activity.first { $0.monthKey == Self.currentMonthKey }?.count ?? 0
    }

    private static var currentMonthKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    private func monthLabel(_ key: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM"
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let date = parser.date(from: key) else { return key }
        let display = DateFormatter()
        display.dateFormat = "MMM"
        display.locale = Locale(identifier: "fr_FR")
        return display.string(from: date)
    }
}
