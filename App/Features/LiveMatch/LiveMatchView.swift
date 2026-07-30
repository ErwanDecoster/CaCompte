import Catalog
import DesignSystem
import Domain
import Store
import SwiftData
import SwiftUI

struct LiveMatchView: View {
    @State private var model: LiveMatchModel
    @State private var draftTexts: [Participant.ID: String] = [:]
    @FocusState private var focusedParticipantID: Participant.ID?
    @State private var isConfirmingManualEnd = false
    @State private var isConfirmingAbandon = false
    @State private var isPresentingShareSession = false
    @State private var isPresentingRoundHistory = false
    @State private var keyboardObserver = KeyboardObserver()

    init(match: MatchRecord, context: ModelContext, catalog: GameCatalog) {
        _model = State(initialValue: try! LiveMatchModel(match: match, context: context, catalog: catalog))
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
                liveView
                    .navigationTitle("\(model.definition.name.fr) · Manche \(model.state.rounds.count + 1)")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var liveView: some View {
        List {
            if model.requiresCloserSelection {
                Section {
                    Text("A fermé la manche").font(.label).foregroundStyle(.textSecondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.sm) {
                            ForEach(model.participants) { participant in
                                Chip(LocalizedStringResource(stringLiteral: participant.displayName), isSelected: model.closedParticipantID == participant.id) {
                                    model.closedParticipantID = participant.id
                                }
                            }
                        }
                    }
                }
            }

            Section {
                ForEach(Array(model.participants.enumerated()), id: \.element.id) { index, participant in
                    HStack(spacing: Space.md) {
                        Text(participant.displayName)
                            .font(index == model.activeSeatIndex ? .h6 : .bodyText)
                            .foregroundStyle(.textPrimary)
                        Spacer()
                        Text((model.totals[participant.id] ?? 0).formatted())
                            .font(.scoreL)
                            .foregroundStyle(.textSecondary)
                            .contentTransition(.numericText())
                            .animation(.default, value: model.totals[participant.id])
                        scoreField(for: participant)
                    }
                    .padding(.vertical, Space.xs)
                    .contentShape(Rectangle())
                    .onTapGesture { focusedParticipantID = participant.id }
                }
            }

            if let message = model.validationErrorMessage {
                Text(message).font(.label).foregroundStyle(.semanticError)
            }
        }
        .listStyle(.plain)
        .toolbar {
            if !model.state.rounds.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Annuler la dernière manche") {
                        model.undoLastRound()
                        draftTexts = [:]
                    }
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Button {
                        isPresentingShareSession = true
                    } label: {
                        Label(
                            model.isSharing ? "Voir la session partagée" : "Partager en direct",
                            systemImage: model.isSharing ? "wifi" : "wifi.circle"
                        )
                    }
                    Button {
                        isPresentingRoundHistory = true
                    } label: {
                        Label("Voir les manches", systemImage: "list.bullet")
                    }
                    if model.canEndManually {
                        Button("Terminer la partie") {
                            isConfirmingManualEnd = true
                        }
                    }
                    Button("Abandonner la partie", role: .destructive) {
                        isConfirmingAbandon = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                if model.definition.scoring.entry.allowsNegative, let current = model.currentParticipant {
                    Button {
                        toggleSign(for: current.id)
                    } label: {
                        Image(systemName: "plusminus")
                    }
                }
                Spacer()
                Button(model.actionLabelTitle) {
                    advance()
                }
            }
        }
        // Doc utilisateur — la barre d'accessoires du clavier (juste au-dessus) disparaît avec
        // lui : sur iPad notamment, le bouton natif de fermeture du clavier laissait l'écran sans
        // aucun moyen de valider la manche en cours (bug remonté). Ce bouton prend le relais,
        // mais uniquement quand le clavier est masqué — sinon il doublonne le « Suivant » déjà
        // présent juste au-dessus (remontée utilisateur).
        .safeAreaInset(edge: .bottom) {
            if !keyboardObserver.isVisible {
                Button(model.actionLabelTitle) {
                    advance()
                }
                .buttonStyle(.primary(size: .medium))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.sm)
                .background(.bar)
            }
        }
        .animation(.default, value: keyboardObserver.isVisible)
        .onAppear {
            focusedParticipantID = model.currentParticipant?.id
        }
        .onChange(of: focusedParticipantID) { _, newValue in
            guard let newValue else { return }
            model.focus(on: newValue)
        }
        .confirmationDialog(
            "Terminer la partie ?",
            isPresented: $isConfirmingManualEnd,
            titleVisibility: .visible
        ) {
            Button("Terminer la partie", role: .destructive) {
                model.endManually()
            }
        } message: {
            Text("Le classement final sera calculé à partir des manches jouées. Cette action ne peut pas être annulée.")
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
        .sheet(isPresented: $isPresentingShareSession) {
            ShareSessionView(model: model)
        }
        .sheet(isPresented: $isPresentingRoundHistory) {
            RoundHistoryView(state: model.state, definition: model.definition)
        }
        // Doc utilisateur — sans ça, la manche d'un contributeur distant se contente de faire
        // monter les totaux (déjà animés juste au-dessus) sans qu'on comprenne pourquoi. Le
        // bandeau nomme l'appareil, le retour haptique attire l'œil même sans le regarder. Même
        // bandeau pour l'explication d'un score modifié par une règle (doublement Skyjo…).
        .overlay(alignment: .top) {
            VStack(spacing: Space.sm) {
                if let message = model.roundExplanationMessage {
                    Banner(LocalizedStringResource(stringLiteral: message))
                }
                if let message = model.remoteActivityMessage {
                    Banner(LocalizedStringResource(stringLiteral: message))
                }
            }
            .padding(.horizontal, Space.lg)
            .padding(.top, Space.sm)
            .frame(maxWidth: .infinity)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        .animation(.default, value: model.remoteActivityMessage)
        .animation(.default, value: model.roundExplanationMessage)
        .sensoryFeedback(.success, trigger: model.remoteActivityMessage) { oldValue, newValue in
            newValue != nil
        }
    }

    /// Charte §5.4 — jamais vide en apparence (placeholder `0`), bordure au focus uniquement.
    /// Clavier système (`.numberPad`) : pas de touche « − », d'où le bouton de signe dans la
    /// barre d'accessoires pour les jeux qui acceptent les valeurs négatives.
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
                let normalized = digits.isEmpty ? sign : sign + digits
                draftTexts[participantID] = normalized
                if let value = Int(normalized) {
                    model.setScore(value, for: participantID)
                } else {
                    model.clearScore(for: participantID)
                }
            }
        )
    }

    private func toggleSign(for participantID: Participant.ID) {
        var text = draftTexts[participantID] ?? ""
        if text.hasPrefix("-") {
            text.removeFirst()
        } else {
            text = "-" + text
        }
        draftTexts[participantID] = text
        if let value = Int(text) {
            model.setScore(value, for: participantID)
        } else {
            model.clearScore(for: participantID)
        }
    }

    private func advance() {
        let committed = model.advance()
        if committed {
            draftTexts = [:]
        }
        focusedParticipantID = model.currentParticipant?.id
    }
}
