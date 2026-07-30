import Catalog
import DesignSystem
import Domain
import Store
import SwiftData
import SwiftUI

struct BeloteRoundView: View {
    @State private var model: BeloteRoundModel
    @State private var isConfirmingAbandon = false
    @State private var isPresentingRoundHistory = false

    init(match: MatchRecord, context: ModelContext, catalog: GameCatalog) {
        _model = State(initialValue: try! BeloteRoundModel(match: match, context: context, catalog: catalog))
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
                Form {
                    Section("Scores") {
                        ForEach(model.teams, id: \.teamID) { team in
                            HStack {
                                Text(teamLabel(team))
                                    .font(.h6)
                                    .foregroundStyle(.textPrimary)
                                Spacer()
                                Text(model.state.total(for: team.members.first?.id ?? UUID()).formatted())
                                    .font(.scoreL)
                                    .foregroundStyle(.textPrimary)
                            }
                        }
                    }

                    Section("Cette donne") {
                        Picker("Équipe preneuse", selection: $model.takerTeamID) {
                            ForEach(model.teams, id: \.teamID) { team in
                                Text(teamLabel(team)).tag(team.teamID)
                            }
                        }
                        .pickerStyle(.segmented)

                        Stepper("Points du preneur : \(model.takerPoints)", value: $model.takerPoints, in: 0...162)

                        Toggle("Capot", isOn: $model.isCapot)
                            .tint(.brandInk)

                        Picker("Belote-rebelote", selection: $model.beloteRebeloteTeamID) {
                            Text("Aucune").tag(String?.none)
                            ForEach(model.teams, id: \.teamID) { team in
                                Text(teamLabel(team)).tag(String?.some(team.teamID))
                            }
                        }
                    }

                    Button("Valider la donne") {
                        model.submit()
                    }
                    .buttonStyle(.primary(size: .medium))
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                .navigationTitle(model.definition.name.fr)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Abandonner la partie", role: .destructive) {
                            isConfirmingAbandon = true
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isPresentingRoundHistory = true
                        } label: {
                            Label("Voir les manches", systemImage: "list.bullet")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingRoundHistory) {
            RoundHistoryView(state: model.state, definition: model.definition)
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

    private func teamLabel(_ team: (teamID: String, members: [Participant])) -> String {
        "Équipe \(team.teamID) (\(team.members.map(\.displayName).joined(separator: " & ")))"
    }
}
