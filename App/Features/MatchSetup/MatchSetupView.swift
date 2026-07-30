import DesignSystem
import Domain
import Store
import SwiftData
import SwiftUI

struct MatchSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: MatchSetupModel
    private let availablePlayers: [PlayerRecord]
    private let onStart: (MatchRecord) -> Void

    init(
        definition: GameDefinition,
        availablePlayers: [PlayerRecord],
        context: ModelContext,
        onStart: @escaping (MatchRecord) -> Void
    ) {
        self.availablePlayers = availablePlayers
        _model = State(initialValue: MatchSetupModel(definition: definition, availablePlayers: availablePlayers, context: context))
        self.onStart = onStart
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Joueurs") {
                    ForEach(availablePlayers) { player in
                        Button {
                            model.toggle(player)
                        } label: {
                            HStack(spacing: Space.md) {
                                AvatarView(avatar: player.avatar, size: .small)
                                Text(player.nickname).foregroundStyle(.textPrimary)
                                Spacer()
                                if model.isSelected(player) {
                                    Image(systemName: "checkmark").foregroundStyle(.brandInk)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if model.definition.players.teams != nil {
                    Section {
                        ForEach(model.selectedPlayers) { player in
                            teamRow(for: player)
                        }
                    } header: {
                        Text("Équipes")
                    } footer: {
                        if !model.teamsAreValid {
                            Text("Chaque équipe doit compter exactement \(model.definition.players.teams?.size ?? 2) joueurs.")
                                .foregroundStyle(.semanticError)
                        }
                    }
                }

                if !model.definition.variants.isEmpty {
                    Section("Variantes") {
                        ForEach(model.definition.variants, id: \.id) { variant in
                            variantRow(variant)
                        }
                    }
                }
            }
            .navigationTitle(model.definition.name.fr)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Commencer") {
                        guard let match = try? model.start() else { return }
                        onStart(match)
                    }
                    .disabled(!model.canStart)
                }
            }
        }
    }

    private func teamRow(for player: PlayerRecord) -> some View {
        HStack {
            Text(player.nickname).foregroundStyle(.textPrimary)
            Spacer()
            Picker("Équipe", selection: Binding(
                get: { model.teamAssignment[player.id] ?? MatchSetupModel.defaultTeamIDs[0] },
                set: { model.assign(player, toTeam: $0) }
            )) {
                ForEach(MatchSetupModel.defaultTeamIDs, id: \.self) { teamID in
                    Text("Équipe \(teamID)").tag(teamID)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
    }

    @ViewBuilder
    private func variantRow(_ variant: GameDefinition.Variant) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            switch variant.kind {
            case .bool:
                Toggle(variant.label.fr, isOn: model.boolBinding(for: variant.id))
                    .tint(.brandInk)
            case .integerChoice:
                Picker(variant.label.fr, selection: model.intBinding(for: variant.id)) {
                    ForEach(Array(variant.values.enumerated()), id: \.offset) { _, value in
                        if case .int(let intValue) = value {
                            Text(intValue.formatted()).tag(intValue)
                        }
                    }
                }
            case .integerRange:
                Stepper(
                    "\(variant.label.fr) : \(model.intBinding(for: variant.id).wrappedValue)",
                    value: model.intBinding(for: variant.id),
                    in: (variant.min ?? 0)...(variant.max ?? 100)
                )
            case .option:
                Picker(variant.label.fr, selection: model.stringBinding(for: variant.id)) {
                    ForEach(Array(variant.values.enumerated()), id: \.offset) { _, value in
                        if case .string(let stringValue) = value {
                            Text(stringValue).tag(stringValue)
                        }
                    }
                }
            }
            if let help = model.help(forVariant: variant.id) {
                Text(help)
                    .font(.label)
                    .foregroundStyle(.textSecondary)
            }
        }
    }
}
