import Catalog
import Domain
import Store
import SwiftData
import SwiftUI

@MainActor
@Observable
final class MatchSetupModel {
    let definition: GameDefinition
    var selectedPlayers: [PlayerRecord] = []
    /// Doc 05 : chaque jeu déclare ses propres variantes (`skyjo.json` a `threshold` et
    /// `doublePenalty`, `yams.json` a `upperBonusThreshold`…) — un dictionnaire générique plutôt
    /// que des propriétés nommées, pour que ce modèle serve tous les jeux du catalogue.
    var variantValues: [String: VariantSelection.Value] = [:]
    /// Doc 05 « Belote » — assignation d'équipe par joueur, vide si le jeu n'en a pas besoin.
    var teamAssignment: [UUID: String] = [:]

    private let repository: MatchRepository

    static let defaultTeamIDs = ["A", "B"]

    var canStart: Bool {
        let countOK = selectedPlayers.count >= definition.players.min && selectedPlayers.count <= definition.players.max
        guard countOK else { return false }
        return definition.players.teams == nil || teamsAreValid
    }

    /// Chaque équipe doit être complète (`teams.size` joueurs), aucune équipe partielle.
    var teamsAreValid: Bool {
        guard let teams = definition.players.teams else { return true }
        guard selectedPlayers.allSatisfy({ teamAssignment[$0.id] != nil }) else { return false }
        let counts = Dictionary(grouping: selectedPlayers) { teamAssignment[$0.id]! }.mapValues(\.count)
        return !counts.isEmpty && counts.values.allSatisfy { $0 == teams.size }
    }

    init(definition: GameDefinition, availablePlayers: [PlayerRecord], context: ModelContext) {
        self.definition = definition
        self.repository = MatchRepository(context: context)
        for variant in definition.variants {
            variantValues[variant.id] = variant.defaultValue
        }

        // Pré-sélection : les habitués de ce jeu s'ils existent, sinon les joueurs créés le
        // plus récemment (ce qui couvre aussi la toute première partie — tout le monde vient
        // d'être créé).
        let recentPlayersForThisGame = ((try? repository.mostRecentParticipants(forGameID: definition.id)) ?? [])
            .filter { last in availablePlayers.contains { $0.id == last.id } }
        if !recentPlayersForThisGame.isEmpty {
            selectedPlayers = recentPlayersForThisGame
        } else {
            let mostRecentlyCreated = availablePlayers.sorted { $0.createdAt > $1.createdAt }
            selectedPlayers = Array(mostRecentlyCreated.prefix(definition.players.max))
        }
        if definition.players.teams != nil {
            reassignTeamsAlternating()
        }
    }

    /// Texte d'aide de la variante, tel que déclaré dans le JSON du jeu.
    func help(forVariant id: String) -> String? {
        definition.variants.first { $0.id == id }?.help?.fr
    }

    func toggle(_ player: PlayerRecord) {
        if let index = selectedPlayers.firstIndex(where: { $0.id == player.id }) {
            selectedPlayers.remove(at: index)
            teamAssignment[player.id] = nil
        } else {
            guard selectedPlayers.count < definition.players.max else { return }
            selectedPlayers.append(player)
        }
        if definition.players.teams != nil {
            reassignTeamsAlternating()
        }
    }

    func isSelected(_ player: PlayerRecord) -> Bool {
        selectedPlayers.contains { $0.id == player.id }
    }

    func assign(_ player: PlayerRecord, toTeam teamID: String) {
        teamAssignment[player.id] = teamID
    }

    /// Répartition par défaut à la sélection : joueurs pairs/impairs alternés entre les
    /// équipes, modifiable ensuite au cas par cas.
    private func reassignTeamsAlternating() {
        guard let teams = definition.players.teams else { return }
        for (index, player) in selectedPlayers.enumerated() {
            let teamIndex = (index / teams.size) % Self.defaultTeamIDs.count
            teamAssignment[player.id] = Self.defaultTeamIDs[teamIndex]
        }
    }

    func intBinding(for variantID: String) -> Binding<Int> {
        Binding(
            get: {
                if case .int(let value) = self.variantValues[variantID] { return value }
                return 0
            },
            set: { self.variantValues[variantID] = .int($0) }
        )
    }

    func boolBinding(for variantID: String) -> Binding<Bool> {
        Binding(
            get: {
                if case .bool(let value) = self.variantValues[variantID] { return value }
                return false
            },
            set: { self.variantValues[variantID] = .bool($0) }
        )
    }

    func stringBinding(for variantID: String) -> Binding<String> {
        Binding(
            get: {
                if case .string(let value) = self.variantValues[variantID] { return value }
                return ""
            },
            set: { self.variantValues[variantID] = .string($0) }
        )
    }

    func start() throws -> MatchRecord {
        let seeds = selectedPlayers.map { player in
            MatchRepository.ParticipantSeed(
                player: player,
                nickname: player.nickname,
                avatarKind: player.avatarKind,
                avatarValue: player.avatarValue,
                paletteID: player.paletteID,
                teamID: teamAssignment[player.id]
            )
        }
        return try repository.createMatch(
            gameID: definition.id,
            rulesVersion: definition.rulesVersion,
            variants: VariantSelection(variantValues),
            seeds: seeds
        )
    }
}
