import Foundation

/// Doc 06 — fonctions pures sur `MatchState` : rien n'est stocké, tout est recalculé à la
/// demande. `insights` sélectionne quatre à six faits parmi une vingtaine de candidats calculés,
/// selon leur intérêt narratif (écart à la normale, unicité, rareté, diversité des sujets).
public struct StatsEngine: Sendable {
    public init() {}

    public func insights(for state: MatchState, definition: GameDefinition) -> [Insight] {
        select(candidates(state: state, definition: definition))
    }

    /// Tous les indicateurs calculés, avant sélection narrative — c'est ce niveau que les
    /// golden files vérifient (spec/README : « un sous-ensemble, pas l'exhaustivité de l'écran »).
    func candidates(state: MatchState, definition: GameDefinition) -> [Insight] {
        computeCandidates(state: state, definition: definition)
    }

    public func series(for state: MatchState) -> [ParticipantSeries] {
        let rounds = state.rounds.sorted { $0.index < $1.index }
        return state.participants.sorted { $0.seatIndex < $1.seatIndex }.map { participant in
            var running = 0
            var points: [ParticipantSeries.Point] = []
            for round in rounds {
                if let entry = round.entries.first(where: { $0.participantID == participant.id }) {
                    running += entry.computedValue
                }
                points.append(ParticipantSeries.Point(round: round.index, total: running))
            }
            return ParticipantSeries(id: participant.id, name: participant.displayName, points: points)
        }
    }

    public func badges(for state: MatchState, definition: GameDefinition) -> [Badge] {
        guard state.rounds.count >= 3 else { return [] }
        let direction = definition.scoring.direction
        let participants = state.participants.sorted { $0.seatIndex < $1.seatIndex }
        let rounds = state.rounds.sorted { $0.index < $1.index }
        let totals = state.totals()

        var candidates: [Participant.ID: [Badge.Kind]] = [:]
        func add(_ kind: Badge.Kind, to id: Participant.ID) {
            candidates[id, default: []].append(kind)
        }

        // Vainqueur.
        guard let extremeTotal = direction == .highestWins ? totals.values.max() : totals.values.min() else {
            return []
        }
        let winners = participants.filter { totals[$0.id] == extremeTotal }
        if winners.count == 1 {
            add(.winner, to: winners[0].id)

            // Photo finish : moins de 3 points d'écart avec le deuxième.
            let sortedTotals = totals.values.sorted(by: direction == .highestWins ? (>) : (<))
            if sortedTotals.count >= 2, abs(sortedTotals[0] - sortedTotals[1]) < 3 {
                add(.photoFinish, to: winners[0].id)
            }
        }

        // Le Métronome / Les montagnes russes.
        let deviations = standardDeviations(rounds: rounds, participants: participants)
        if deviations.count >= 2 {
            let average = deviations.values.reduce(0, +) / Double(deviations.count)
            if let (lowestID, lowestValue) = deviations.min(by: { $0.value < $1.value }), average > 0, lowestValue < average * 0.6 {
                add(.metronome, to: lowestID)
            }
            if let (highestID, highestValue) = deviations.max(by: { $0.value < $1.value }), average > 0, highestValue > average * 1.6 {
                add(.rollercoaster, to: highestID)
            }
        }

        // Le Kamikaze : détient le plus gros tour, uniquement si le plus bas gagne.
        if direction == .lowestWins, let (participantID, _, _) = extremeSingleRound(rounds: rounds, pick: .max) {
            add(.kamikaze, to: participantID)
        }

        // Imperturbable : en tête pendant ≥ 80 % des manches.
        let leaders = leaderSequence(rounds: rounds, participants: participants, direction: direction)
        if !leaders.isEmpty {
            let counts = Dictionary(grouping: leaders, by: { $0 }).mapValues(\.count)
            if let (leaderID, count) = counts.max(by: { $0.value < $1.value }), Double(count) / Double(leaders.count) >= 0.8 {
                add(.unshakeable, to: leaderID)
            }
        }

        // La Remontada : gain ≥ 3 places entre le pire rang atteint et le rang final.
        let rankSeries = rankSequence(rounds: rounds, participants: participants, direction: direction)
        for participant in participants {
            guard let ranks = rankSeries[participant.id], let worst = ranks.max(), let final = ranks.last else { continue }
            if worst - final >= 3 {
                add(.comeback, to: participant.id)
            }
        }

        // Priorité : le badge le plus rare l'emporte, un seul par joueur.
        let rarityOrder: [Badge.Kind] = [.photoFinish, .comeback, .rollercoaster, .metronome, .unshakeable, .kamikaze, .winner]
        return candidates.compactMap { participantID, kinds -> Badge? in
            guard let kind = rarityOrder.first(where: { kinds.contains($0) }) else { return nil }
            return Badge(kind: kind, participantID: participantID)
        }
    }

    // MARK: - Candidats d'insight

    private func computeCandidates(state: MatchState, definition: GameDefinition) -> [Insight] {
        let rounds = state.rounds.sorted { $0.index < $1.index }
        guard !rounds.isEmpty else { return [] }

        let direction = definition.scoring.direction
        let participants = state.participants.sorted { $0.seatIndex < $1.seatIndex }
        let totals = state.totals()
        let nameByID = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, $0.displayName) })

        var results: [Insight] = []

        let allValues = rounds.flatMap { $0.entries.map { Double($0.computedValue) } }
        let overallMean = allValues.reduce(0, +) / Double(max(allValues.count, 1))
        let overallSpread = max(standardDeviation(of: allValues, mean: overallMean), 1)

        if let (participantID, value, round) = extremeSingleRound(rounds: rounds, pick: .max) {
            let z = abs(value - overallMean) / overallSpread
            results.append(Insight(
                id: .highestRoundScore,
                headline: "Plus gros tour",
                detail: "\(nameByID[participantID] ?? "?") — \(Int(value)) points, manche \(round + 1)",
                symbol: "flame.fill",
                value: .single(participantID: participantID, value: value, round: round),
                interestScore: z
            ))
        }

        if let (participantID, value, round) = extremeSingleRound(rounds: rounds, pick: direction == .highestWins ? .max : .min) {
            let z = abs(value - overallMean) / overallSpread
            results.append(Insight(
                id: .bestRoundScore,
                headline: "Meilleur tour",
                detail: "\(nameByID[participantID] ?? "?") — \(Int(value)) points, manche \(round + 1)",
                symbol: "star.fill",
                value: .single(participantID: participantID, value: value, round: round),
                interestScore: z * 0.9
            ))
        }

        let deviations = standardDeviations(rounds: rounds, participants: participants)
        if deviations.count >= 2 {
            let average = deviations.values.reduce(0, +) / Double(deviations.count)
            if let (lowestID, lowestValue) = deviations.min(by: { $0.value < $1.value }) {
                results.append(Insight(
                    id: .mostRegular,
                    headline: "Le Métronome",
                    detail: "\(nameByID[lowestID] ?? "?") — écart-type \(String(format: "%.2f", lowestValue))",
                    symbol: "metronome",
                    value: .single(participantID: lowestID, value: (lowestValue * 100).rounded() / 100, round: nil),
                    interestScore: average > 0 ? (average - lowestValue) / average : 0
                ))
            }
            if let (highestID, highestValue) = deviations.max(by: { $0.value < $1.value }) {
                results.append(Insight(
                    id: .mostIrregular,
                    headline: "Les montagnes russes",
                    detail: "\(nameByID[highestID] ?? "?") — écart-type \(String(format: "%.2f", highestValue))",
                    symbol: "chart.line.uptrend.xyaxis",
                    value: .single(participantID: highestID, value: (highestValue * 100).rounded() / 100, round: nil),
                    interestScore: average > 0 ? (highestValue - average) / average : 0
                ))
            }
        }

        let sortedTotals = totals.values.sorted(by: direction == .highestWins ? (>) : (<))
        if sortedTotals.count >= 2 {
            let gap = Double(abs(sortedTotals[0] - sortedTotals[1]))
            let relativeGap = overallSpread > 0 ? gap / overallSpread : gap
            results.append(Insight(
                id: .finalGap,
                headline: "Écart final",
                detail: "\(Int(gap)) points entre le premier et le deuxième",
                symbol: "arrow.left.and.right",
                value: .single(participantID: nil, value: gap, round: nil),
                interestScore: relativeGap < 0.5 ? (0.5 - relativeGap) * 2 : 0
            ))
        }

        let leaders = leaderSequence(rounds: rounds, participants: participants, direction: direction)
        if !leaders.isEmpty {
            let changes = zip(leaders, leaders.dropFirst()).filter { $0 != $1 }.count
            results.append(Insight(
                id: .leadChanges,
                headline: "Changements de tête",
                detail: changes == 0 ? "Domination du début à la fin" : "\(changes) changement(s) de leader",
                symbol: "arrow.left.arrow.right",
                value: .single(participantID: nil, value: Double(changes), round: nil),
                interestScore: changes == 0 ? 1.2 : (changes >= 4 ? 1.0 : 0.2)
            ))

            if let (leaderID, streak) = longestStreak(in: leaders) {
                results.append(Insight(
                    id: .longestLeadStreak,
                    headline: "Plus longue série en tête",
                    detail: "\(nameByID[leaderID] ?? "?") — \(streak) manche(s) d'affilée",
                    symbol: "crown.fill",
                    value: .single(participantID: leaderID, value: Double(streak), round: nil),
                    interestScore: Double(streak) / Double(rounds.count)
                ))
            }
        }

        if definition.statsProfiles.contains("skyjo") {
            var closedCounts: [Participant.ID: Double] = [:]
            var doubledCounts: [Participant.ID: Double] = [:]
            for participant in participants {
                closedCounts[participant.id] = 0
                doubledCounts[participant.id] = 0
            }
            for round in rounds {
                for entry in round.entries {
                    if entry.modifiers.contains(.closedRound) {
                        closedCounts[entry.participantID, default: 0] += 1
                    }
                    if entry.computedValue != entry.rawValue {
                        doubledCounts[entry.participantID, default: 0] += 1
                    }
                }
            }
            results.append(Insight(
                id: .roundsClosed,
                headline: "Manches fermées",
                detail: "Répartition des fermetures de manche",
                symbol: "lock.fill",
                value: .perParticipant(closedCounts),
                interestScore: 0.3
            ))
            results.append(Insight(
                id: .doublingsSuffered,
                headline: "Doublements subis",
                detail: "Répartition des scores doublés",
                symbol: "multiply.circle.fill",
                value: .perParticipant(doubledCounts),
                interestScore: doubledCounts.values.contains(where: { $0 > 0 }) ? 0.5 : 0.1
            ))
        }

        return results
    }

    private func select(_ candidates: [Insight]) -> [Insight] {
        var remaining = candidates
        var selected: [Insight] = []
        var mentionCounts: [Participant.ID: Int] = [:]

        while selected.count < 6, !remaining.isEmpty {
            let scored = remaining.map { insight -> (Insight, Double) in
                let penalty = insight.mentionedParticipants.reduce(0.0) { $0 + Double(mentionCounts[$1] ?? 0) } * 0.3
                return (insight, insight.interestScore - penalty)
            }
            guard let (best, score) = scored.max(by: { $0.1 < $1.1 }) else { break }
            guard score > 0.2 || selected.isEmpty else { break }
            selected.append(best)
            for participant in best.mentionedParticipants {
                mentionCounts[participant, default: 0] += 1
            }
            remaining.removeAll { $0.id == best.id && $0.value == best.value }
        }
        return selected
    }

    // MARK: - Aides de calcul

    private enum Extreme { case max, min }

    private func extremeSingleRound(rounds: [Round], pick: Extreme) -> (Participant.ID, Double, Int)? {
        var best: (Participant.ID, Double, Int)?
        for round in rounds {
            for entry in round.entries {
                let value = Double(entry.computedValue)
                guard let current = best else {
                    best = (entry.participantID, value, round.index)
                    continue
                }
                let better = pick == .max ? value > current.1 : value < current.1
                if better {
                    best = (entry.participantID, value, round.index)
                }
            }
        }
        return best
    }

    private func standardDeviation(of values: [Double], mean: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let variance = values.reduce(0) { partial, value in
            let deviation = value - mean
            return partial + deviation * deviation
        } / Double(values.count)
        return variance.squareRoot()
    }

    private func standardDeviations(rounds: [Round], participants: [Participant]) -> [Participant.ID: Double] {
        var result: [Participant.ID: Double] = [:]
        for participant in participants {
            let values = rounds.compactMap { round in
                round.entries.first { $0.participantID == participant.id }?.computedValue
            }.map(Double.init)
            guard values.count > 1 else {
                result[participant.id] = 0
                continue
            }
            let mean = values.reduce(0, +) / Double(values.count)
            result[participant.id] = standardDeviation(of: values, mean: mean)
        }
        return result
    }

    private func currentLeader(totals: [Participant.ID: Int], participants: [Participant], direction: Direction) -> Participant.ID {
        var best = participants[0]
        var bestValue = totals[best.id] ?? 0
        for participant in participants.dropFirst() {
            let value = totals[participant.id] ?? 0
            let better = direction == .highestWins ? value > bestValue : value < bestValue
            if better {
                best = participant
                bestValue = value
            }
        }
        return best.id
    }

    private func leaderSequence(rounds: [Round], participants: [Participant], direction: Direction) -> [Participant.ID] {
        var running: [Participant.ID: Int] = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, 0) })
        var sequence: [Participant.ID] = []
        for round in rounds {
            for entry in round.entries {
                running[entry.participantID, default: 0] += entry.computedValue
            }
            sequence.append(currentLeader(totals: running, participants: participants, direction: direction))
        }
        return sequence
    }

    private func longestStreak(in sequence: [Participant.ID]) -> (Participant.ID, Int)? {
        guard !sequence.isEmpty else { return nil }
        var bestID = sequence[0]
        var bestLength = 1
        var currentID = sequence[0]
        var currentLength = 1
        for id in sequence.dropFirst() {
            if id == currentID {
                currentLength += 1
            } else {
                currentID = id
                currentLength = 1
            }
            if currentLength > bestLength {
                bestLength = currentLength
                bestID = currentID
            }
        }
        return (bestID, bestLength)
    }

    private func rankSequence(rounds: [Round], participants: [Participant], direction: Direction) -> [Participant.ID: [Int]] {
        var running: [Participant.ID: Int] = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, 0) })
        var series: [Participant.ID: [Int]] = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, []) })

        for round in rounds {
            for entry in round.entries {
                running[entry.participantID, default: 0] += entry.computedValue
            }
            let ordered = participants.map(\.id).sorted { lhs, rhs in
                let l = running[lhs] ?? 0
                let r = running[rhs] ?? 0
                return direction == .highestWins ? l > r : l < r
            }
            for (index, id) in ordered.enumerated() {
                series[id, default: []].append(index + 1)
            }
        }
        return series
    }
}

private extension Insight {
    var mentionedParticipants: [Participant.ID] {
        switch value {
        case .single(let participantID, _, _):
            participantID.map { [$0] } ?? []
        case .perParticipant(let map):
            Array(map.keys)
        }
    }
}
