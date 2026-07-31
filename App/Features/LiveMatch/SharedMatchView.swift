import DesignSystem
import Domain
import SwiftUI

/// Doc 09 — l'écran d'un pair non-hôte. Observateur : lecture seule, le tableau se met à jour
/// tout seul à mesure que l'hôte diffuse. Contributeur : les mêmes champs que `LiveMatchView`,
/// mais « Envoyer » propose la manche à l'hôte au lieu de l'écrire directement — elle n'apparaît
/// aux autres qu'une fois acceptée.
struct SharedMatchView: View {
    let model: SharedMatchModel
    /// Doc utilisateur P9 — `MatchConnectionCoordinator` retente déjà seul, toutes les quelques
    /// secondes, tant que cet écran affiche une perte de connexion : ce bouton ne sert qu'à forcer
    /// une tentative immédiate plutôt que d'attendre la prochaine. Retourne si la tentative a
    /// abouti, pour qu'un échec affiche un vrai message plutôt qu'un aller-retour silencieux vers
    /// l'état initial.
    let onReconnect: () async -> Bool
    @State private var isReconnecting = false
    @State private var reconnectFailed = false
    @State private var draftTexts: [Participant.ID: String] = [:]
    @State private var closedParticipantID: Participant.ID?
    @FocusState private var focusedParticipantID: Participant.ID?
    @State private var activeIndex = 0
    @State private var isPresentingRoundHistory = false
    @State private var keyboardObserver = KeyboardObserver()

    var body: some View {
        Group {
            if let definition = model.definition, let state = model.state {
                liveView(definition: definition, state: state)
            } else {
                ProgressView("Connexion à la partie…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var navigationTitle: String {
        guard let definition = model.definition else { return "Partie partagée" }
        let roundNumber = (model.state?.rounds.count ?? 0) + 1
        return "\(definition.name.fr) · Manche \(roundNumber)"
    }

    private func requiresCloserSelection(_ definition: GameDefinition) -> Bool {
        definition.scoring.modifiers.contains { $0.kind == .exclusiveFlag && $0.required }
    }

    private func liveView(definition: GameDefinition, state: MatchState) -> some View {
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
                        Text(reconnectFailed ? "Toujours pas de connexion — nouvelle tentative automatique en cours." : "Reprise automatique en cours.")
                            .font(.bodySmall)
                            .foregroundStyle(.textTertiary)
                        Button(isReconnecting ? "Reconnexion…" : "Réessayer maintenant") {
                            Task {
                                isReconnecting = true
                                reconnectFailed = false
                                let succeeded = await onReconnect()
                                isReconnecting = false
                                reconnectFailed = !succeeded
                            }
                        }
                        .disabled(isReconnecting)
                    }
                }
            }

            if model.canPropose, requiresCloserSelection(definition) {
                Section {
                    Text("A fermé la manche").font(.label).foregroundStyle(.textSecondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.sm) {
                            ForEach(model.participants) { participant in
                                Chip(LocalizedStringResource(stringLiteral: participant.displayName), isSelected: closedParticipantID == participant.id) {
                                    closedParticipantID = participant.id
                                }
                            }
                        }
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

            if !model.canPropose {
                Section {
                    Text("Tu observes cette partie : la saisie se fait sur l'appareil de l'hôte ou d'un contributeur.")
                        .font(.bodySmall)
                        .foregroundStyle(.textTertiary)
                }
            }
        }
        .listStyle(.plain)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingRoundHistory = true
                } label: {
                    Label("Voir les manches", systemImage: "list.bullet")
                }
            }
            if model.canPropose {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(isLastField ? "Envoyer" : "Suivant") {
                        advanceFocus()
                    }
                }
            }
        }
        // Doc utilisateur — même bug que `LiveMatchView` : la barre d'accessoires du clavier
        // disparaît avec lui, laissant l'écran sans moyen de valider la manche. Masqué quand le
        // clavier est visible pour ne pas doublonner son propre bouton « Suivant/Envoyer ».
        .safeAreaInset(edge: .bottom) {
            if model.canPropose, !keyboardObserver.isVisible {
                Button(isLastField ? "Envoyer" : "Suivant") {
                    advanceFocus()
                }
                .buttonStyle(.primary(size: .medium))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.sm)
                .background(.bar)
            }
        }
        .animation(.default, value: keyboardObserver.isVisible)
        .sheet(isPresented: $isPresentingRoundHistory) {
            RoundHistoryView(state: state, definition: definition)
        }
        .overlay(alignment: .top) {
            if let message = model.roundExplanationMessage {
                Banner(LocalizedStringResource(stringLiteral: message))
                    .padding(.horizontal, Space.lg)
                    .padding(.top, Space.sm)
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.default, value: model.roundExplanationMessage)
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
            ScoreInput(
                participantID: participant.id,
                rawValue: Int(draftTexts[participant.id] ?? "") ?? 0,
                modifiers: participant.id == closedParticipantID ? [.closedRound] : []
            )
        }
        await model.propose(inputs)
        draftTexts = [:]
        closedParticipantID = nil
    }
}
