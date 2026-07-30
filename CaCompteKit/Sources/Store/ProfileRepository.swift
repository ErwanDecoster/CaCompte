import Domain
import Foundation
import SwiftData

/// Doc 06 « Statistiques de profil » — parcourt tout l'historique d'un joueur. Calcul à la
/// demande, aucune pré-agrégation persistée (doc 06 : « un agrégat stocké est un agrégat qui
/// finira désynchronisé »).
@MainActor
public struct ProfileRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func stats(for player: PlayerRecord, catalog: GameCatalog) throws -> ProfileStats {
        // Filtrage en mémoire plutôt qu'un `#Predicate` chaînant la relation optionnelle
        // (`$0.player?.id`, ou une égalité de modèle) : les deux plantent ou ne compilent pas
        // avec ce traducteur de prédicat SwiftData. Volume attendu compatible (doc 06).
        let playerID = player.id
        let participations = try context.fetch(FetchDescriptor<ParticipantRecord>())
            .filter { $0.player?.id == playerID && $0.match?.statusRaw == MatchStatus.ended.rawValue }

        guard !participations.isEmpty else { return .empty }

        let played = participations.count
        let wins = participations.filter { $0.finalRank == 1 }.count
        let winRate = Double(wins) / Double(played)

        let ranks = participations.compactMap(\.finalRank)
        let averageRank = ranks.isEmpty ? 0 : Double(ranks.reduce(0, +)) / Double(ranks.count)

        let normalizedRanks: [Double] = participations.compactMap { participant in
            guard let rank = participant.finalRank, let match = participant.match else { return nil }
            let playerCount = match.participants.count
            guard playerCount > 1 else { return nil }
            return Double(playerCount - rank) / Double(playerCount - 1)
        }
        let averageNormalizedRank = normalizedRanks.isEmpty
            ? 0
            : normalizedRanks.reduce(0, +) / Double(normalizedRanks.count)

        let (currentStreak, bestStreak) = winStreaks(participations: participations)

        return ProfileStats(
            played: played,
            wins: wins,
            winRate: winRate,
            averageRank: averageRank,
            averageNormalizedRank: averageNormalizedRank,
            byGame: gameBreakdowns(participations: participations, catalog: catalog),
            nemesis: computeNemesis(playerID: player.id, participations: participations),
            currentWinStreak: currentStreak,
            bestWinStreak: bestStreak,
            activity: monthlyActivity(participations: participations)
        )
    }

    private func gameBreakdowns(participations: [ParticipantRecord], catalog: GameCatalog) -> [ProfileStats.GameBreakdown] {
        let byGameID = Dictionary(grouping: participations) { $0.match?.gameID ?? "" }
        return byGameID.compactMap { gameID, entries -> ProfileStats.GameBreakdown? in
            guard !gameID.isEmpty else { return nil }
            let rulesVersion = entries.first?.match?.rulesVersion ?? 1
            let definition = try? catalog.definition(for: gameID, version: rulesVersion)
            let name = definition?.name.fr ?? gameID
            let direction = definition?.scoring.direction ?? .lowestWins

            let played = entries.count
            let wins = entries.filter { $0.finalRank == 1 }.count
            let winRate = played > 0 ? Double(wins) / Double(played) : 0

            let scored: [(value: Int, date: Date)] = entries.compactMap { entry in
                guard let score = entry.finalScore, let date = entry.match?.startedAt else { return nil }
                return (score, date)
            }
            let best = direction == .highestWins ? scored.max { $0.value < $1.value } : scored.min { $0.value < $1.value }
            let worst = direction == .highestWins ? scored.min { $0.value < $1.value } : scored.max { $0.value < $1.value }

            return ProfileStats.GameBreakdown(
                gameID: gameID,
                gameName: name,
                played: played,
                wins: wins,
                winRate: winRate,
                bestScore: best,
                worstScore: worst
            )
        }.sorted { $0.played > $1.played }
    }

    /// Doc 06 : adversaire croisé au moins 5 fois avec le plus faible taux de victoire.
    private func computeNemesis(playerID: UUID, participations: [ParticipantRecord]) -> ProfileStats.Nemesis? {
        struct Aggregate {
            var name: String
            var together = 0
            var wins = 0
        }
        var byOpponent: [UUID: Aggregate] = [:]

        for participation in participations {
            guard let match = participation.match else { continue }
            let won = participation.finalRank == 1
            for opponent in match.participants {
                guard let opponentPlayer = opponent.player, opponentPlayer.id != playerID else { continue }
                var aggregate = byOpponent[opponentPlayer.id] ?? Aggregate(name: opponent.nicknameSnapshot)
                aggregate.together += 1
                if won { aggregate.wins += 1 }
                aggregate.name = opponent.nicknameSnapshot
                byOpponent[opponentPlayer.id] = aggregate
            }
        }

        return byOpponent
            .filter { $0.value.together >= 5 }
            .map { id, aggregate in
                ProfileStats.Nemesis(
                    playerID: id,
                    name: aggregate.name,
                    matchesTogether: aggregate.together,
                    winRateWithThemPresent: Double(aggregate.wins) / Double(aggregate.together)
                )
            }
            .min { $0.winRateWithThemPresent < $1.winRateWithThemPresent }
    }

    private func winStreaks(participations: [ParticipantRecord]) -> (current: Int, best: Int) {
        let ordered = participations.sorted { ($0.match?.startedAt ?? .distantPast) < ($1.match?.startedAt ?? .distantPast) }
        var best = 0
        var running = 0
        for participation in ordered {
            if participation.finalRank == 1 {
                running += 1
                best = max(best, running)
            } else {
                running = 0
            }
        }
        return (current: running, best: best)
    }

    private func monthlyActivity(participations: [ParticipantRecord]) -> [ProfileStats.MonthActivity] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current

        var counts: [String: Int] = [:]
        for participation in participations {
            guard let date = participation.match?.startedAt else { continue }
            counts[formatter.string(from: date), default: 0] += 1
        }

        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        var months: [ProfileStats.MonthActivity] = []
        for offset in stride(from: 11, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .month, value: -offset, to: now) else { continue }
            let key = formatter.string(from: date)
            months.append(ProfileStats.MonthActivity(monthKey: key, count: counts[key] ?? 0))
        }
        return months
    }
}
