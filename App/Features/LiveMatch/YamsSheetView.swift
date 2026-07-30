import Catalog
import DesignSystem
import Domain
import Store
import SwiftData
import SwiftUI

struct YamsSheetView: View {
    @State private var model: YamsSheetModel
    @State private var pendingEntry: PendingEntry?
    @State private var isConfirmingAbandon = false

    init(match: MatchRecord, context: ModelContext, catalog: GameCatalog) {
        _model = State(initialValue: try! YamsSheetModel(match: match, context: context, catalog: catalog))
    }

    private struct PendingEntry: Identifiable {
        let participant: Participant
        let category: GameDefinition.Category
        var id: String { "\(participant.id)-\(category.id)" }
    }

    private var upperCategories: [GameDefinition.Category] {
        model.categories.filter { $0.section == .upper }
    }

    private var lowerCategories: [GameDefinition.Category] {
        model.categories.filter { $0.section == .lower }
    }

    var body: some View {
        Group {
            if model.isConcluded {
                ResultsView(
                    state: model.state,
                    definition: model.definition,
                    standings: model.finalStandings,
                    participantRecords: model.participantRecords
                )
            } else {
                sheetGrid
                    .navigationTitle(model.definition.name.fr)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Abandonner la partie", role: .destructive) {
                                isConfirmingAbandon = true
                            }
                        }
                    }
            }
        }
        .sheet(item: $pendingEntry) { pending in
            YamsCategoryEntrySheet(participant: pending.participant, category: pending.category) { rawValue in
                model.submit(rawValue: rawValue, participantID: pending.participant.id, categoryID: pending.category.id)
            }
        }
        .alert(
            "Saisie invalide",
            isPresented: Binding(get: { model.validationErrorMessage != nil }, set: { if !$0 { model.dismissError() } })
        ) {
            Button("OK") {}
        } message: {
            Text(model.validationErrorMessage ?? "")
        }
        .confirmationDialog(
            "Abandonner cette partie ?",
            isPresented: $isConfirmingAbandon,
            titleVisibility: .visible
        ) {
            Button("Abandonner", role: .destructive) {
                model.abandon()
            }
        } message: {
            Text("La partie sera classée comme abandonnée dans l'historique, avec le classement atteint jusque-là. Cette action ne peut pas être annulée.")
        }
    }

    private var sheetGrid: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: Space.lg, verticalSpacing: Space.sm) {
                GridRow {
                    Text("").frame(width: 130, alignment: .leading)
                    ForEach(model.participants) { participant in
                        Text(participant.displayName)
                            .font(.label)
                            .foregroundStyle(.textSecondary)
                            .frame(width: 72)
                    }
                }
                ForEach(upperCategories, id: \.id) { category in
                    categoryRow(category)
                }
                GridRow {
                    Text("Bonus").font(.label).foregroundStyle(.textTertiary).frame(width: 130, alignment: .leading)
                    ForEach(model.participants) { participant in
                        Text(bonusText(for: participant.id))
                            .font(.bodySmall)
                            .foregroundStyle(.textTertiary)
                            .frame(width: 72)
                    }
                }
                Divider().gridCellColumns(model.participants.count + 1)
                ForEach(lowerCategories, id: \.id) { category in
                    categoryRow(category)
                }
                Divider().gridCellColumns(model.participants.count + 1)
                GridRow {
                    Text("Total").font(.h6).foregroundStyle(.textPrimary).frame(width: 130, alignment: .leading)
                    ForEach(model.participants) { participant in
                        Text(model.state.total(for: participant.id).formatted())
                            .font(.scoreM)
                            .foregroundStyle(.textPrimary)
                            .frame(width: 72)
                    }
                }
            }
            .padding(Space.lg)
        }
    }

    private func categoryRow(_ category: GameDefinition.Category) -> some View {
        GridRow {
            Text(category.label.fr)
                .font(.bodySmall)
                .foregroundStyle(.textPrimary)
                .frame(width: 130, alignment: .leading)
            ForEach(model.participants) { participant in
                cell(participant: participant, category: category)
            }
        }
    }

    private func cell(participant: Participant, category: GameDefinition.Category) -> some View {
        let filled = model.filledCategories(for: participant.id)
        return Group {
            if let entry = filled[category.id] {
                Text(entry.computedValue.formatted())
                    .font(.bodyText)
                    .foregroundStyle(.textPrimary)
            } else {
                Button {
                    pendingEntry = PendingEntry(participant: participant, category: category)
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: IconSize.md))
                        .foregroundStyle(.brandTeal)
                }
            }
        }
        .frame(width: 72)
    }

    private func bonusText(for participantID: Participant.ID) -> String {
        let filled = model.filledCategories(for: participantID)
        guard upperCategories.allSatisfy({ filled[$0.id] != nil }) else { return "—" }
        let hasBonus = upperCategories.contains { filled[$0.id]?.explanation != nil }
        return hasBonus ? "+35" : "0"
    }
}

private struct YamsCategoryEntrySheet: View {
    let participant: Participant
    let category: GameDefinition.Category
    let onSubmit: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var diceCount = 0
    @State private var sum = 0
    @State private var achieved = true

    var body: some View {
        NavigationStack {
            VStack(spacing: Space.xl) {
                VStack(spacing: Space.xxs) {
                    Text(participant.displayName).font(.h4).foregroundStyle(.textPrimary)
                    Text(category.label.fr).font(.h6).foregroundStyle(.textSecondary)
                }

                switch category.scoring.kind {
                case .multipleOf:
                    VStack(spacing: Space.md) {
                        Stepper("Nombre de dés : \(diceCount)", value: $diceCount, in: 0...5)
                        Text("\(diceCount * (category.scoring.value ?? 0)) points")
                            .font(.scoreL)
                            .foregroundStyle(.textPrimary)
                    }
                case .sumOfDice:
                    Stepper("Somme : \(sum)", value: $sum, in: 0...(category.scoring.max ?? 30))
                case .fixed:
                    Picker("", selection: $achieved) {
                        Text("Obtenu (\(category.scoring.value ?? 0))").tag(true)
                        Text("Raté (0)").tag(false)
                    }
                    .pickerStyle(.segmented)
                }

                Spacer(minLength: 0)

                Button("Valider") {
                    let rawValue: Int
                    switch category.scoring.kind {
                    case .multipleOf: rawValue = diceCount
                    case .sumOfDice: rawValue = sum
                    case .fixed: rawValue = achieved ? 1 : 0
                    }
                    onSubmit(rawValue)
                    dismiss()
                }
                .buttonStyle(.primary(size: .medium))
                .frame(maxWidth: .infinity)
            }
            .padding(Space.lg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
