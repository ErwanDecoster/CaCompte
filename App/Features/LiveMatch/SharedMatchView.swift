import DesignSystem
import Domain
import SwiftUI

/// Doc 09 — l'écran d'un pair non-hôte. Observateur : lecture seule, le tableau se met à jour
/// tout seul à mesure que l'hôte diffuse. Contributeur : les mêmes champs que `LiveMatchView`,
/// mais « Envoyer » propose la manche à l'hôte au lieu de l'écrire directement — elle n'apparaît
/// aux autres qu'une fois acceptée.
struct SharedMatchView: View {
    let model: SharedMatchModel
    @State private var draftTexts: [Participant.ID: String] = [:]
    @FocusState private var focusedParticipantID: Participant.ID?
    @State private var activeIndex = 0

    var body: some View {
        Group {
            if let definition = model.definition {
                liveView(definition: definition)
            } else {
                ProgressView("Connexion à la partie…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(model.definition?.name.fr ?? "Partie partagée")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func liveView(definition: GameDefinition) -> some View {
        List {
            if !model.isHostConnected {
                Section {
                    if model.isConcluded {
                        Text("La partie est terminée.")
                            .font(.label)
                            .foregroundStyle(.textSecondary)
                    } else {
                        Text("Connexion à l'hôte perdue. Le tableau affiché est le dernier reçu.")
                            .font(.label)
                            .foregroundStyle(.semanticError)
                    }
                }
            }

            Section {
                ForEach(model.participants) { participant in
                    HStack(spacing: Space.md) {
                        Text(participant.displayName)
                            .font(.bodyText)
                            .foregroundStyle(.textPrimary)
                        Spacer()
                        Text((model.totals[participant.id] ?? 0).formatted())
                            .font(.scoreL)
                            .foregroundStyle(.textSecondary)
                        if model.canPropose {
                            scoreField(for: participant)
                        }
                    }
                    .padding(.vertical, Space.xs)
                    .contentShape(Rectangle())
                    .onTapGesture { focusedParticipantID = participant.id }
                }
            }

            if let reason = model.latestRejectionReason {
                Text(reason).font(.label).foregroundStyle(.semanticError)
            }

            if model.canPropose {
                Section {
                    Button("Envoyer la manche") {
                        Task { await sendRound() }
                    }
                    .buttonStyle(.primary())
                    .disabled(!model.isHostConnected)
                }
            } else {
                Section {
                    Text("Tu observes cette partie : la saisie se fait sur l'appareil de l'hôte ou d'un contributeur.")
                        .font(.bodySmall)
                        .foregroundStyle(.textTertiary)
                }
            }
        }
        .listStyle(.plain)
        .toolbar {
            if model.canPropose {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(isLastField ? "Envoyer" : "Suivant") {
                        advanceFocus()
                    }
                }
            }
        }
        .onChange(of: focusedParticipantID) { _, newValue in
            guard let newValue, let index = model.participants.firstIndex(where: { $0.id == newValue }) else { return }
            activeIndex = index
        }
    }

    /// Doc utilisateur (recette iPad) — sans cette barre d'accessoires, chaque champ devait être
    /// tapé à la main l'un après l'autre. `LiveMatchView` (l'hôte) a déjà cet enchaînement ;
    /// `SharedMatchView` en avait été privée par oubli, pas par choix.
    private var isLastField: Bool {
        activeIndex >= model.participants.count - 1
    }

    private func advanceFocus() {
        guard isLastField else {
            activeIndex += 1
            focusedParticipantID = model.participants[activeIndex].id
            return
        }
        Task { await sendRound() }
    }

    private func scoreField(for participant: Participant) -> some View {
        TextField("0", text: textBinding(for: participant.id))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .font(.scoreM)
            .foregroundStyle(.textPrimary)
            .padding(.horizontal, Space.md)
            .frame(width: 88, height: ButtonHeight.medium)
            .background(.neutralFill, in: .rect(cornerRadius: Radius.sm))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.sm)
                    .strokeBorder(.brandInk, lineWidth: focusedParticipantID == participant.id ? 2 : 0)
            }
            .focused($focusedParticipantID, equals: participant.id)
    }

    private func textBinding(for participantID: Participant.ID) -> Binding<String> {
        Binding(
            get: { draftTexts[participantID] ?? "" },
            set: { newValue in
                let sign = newValue.hasPrefix("-") ? "-" : ""
                let digits = newValue.filter(\.isNumber)
                draftTexts[participantID] = digits.isEmpty ? sign : sign + digits
            }
        )
    }

    private func sendRound() async {
        let inputs = model.participants.map { participant in
            ScoreInput(participantID: participant.id, rawValue: Int(draftTexts[participant.id] ?? "") ?? 0)
        }
        await model.propose(inputs)
        draftTexts = [:]
    }
}
