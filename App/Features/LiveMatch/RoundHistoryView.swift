import DesignSystem
import Domain
import SwiftUI

/// Doc utilisateur — « voir les manches précédentes » en cours de partie (jusqu'ici, le détail
/// manche par manche n'existait que dans `ResultsView`, une fois la partie terminée). Ordonné par
/// siège plutôt que par classement : le classement change à chaque manche en cours de partie,
/// l'ordre des sièges reste stable — et `Participant.displayName` (pas `ParticipantRecord`) parce
/// que cette vue doit marcher aussi bien côté pair (`SharedMatchModel`, pas de fiche joueur locale)
/// que côté hôte.
struct RoundHistoryView: View {
    let state: MatchState
    let definition: GameDefinition
    @Environment(\.dismiss) private var dismiss

    private var participants: [Participant] {
        state.participants.sorted { $0.seatIndex < $1.seatIndex }
    }

    private var rounds: [Round] {
        state.rounds.sorted { $0.index < $1.index }
    }

    var body: some View {
        NavigationStack {
            Group {
                if rounds.isEmpty {
                    EmptyState(icon: "list.bullet", message: "Aucune manche jouée pour l'instant.")
                } else {
                    ScrollView {
                        Card {
                            ScrollView(.horizontal, showsIndicators: false) {
                                Grid(alignment: .leading, horizontalSpacing: Space.lg, verticalSpacing: Space.xs) {
                                    GridRow {
                                        Text("").frame(width: 24, alignment: .leading)
                                        ForEach(participants) { participant in
                                            Text(participant.displayName)
                                                .font(.label)
                                                .foregroundStyle(.textSecondary)
                                        }
                                    }
                                    ForEach(rounds, id: \.index) { round in
                                        GridRow {
                                            Text("\(round.index + 1)")
                                                .font(.label)
                                                .foregroundStyle(.textTertiary)
                                                .frame(width: 24, alignment: .leading)
                                            ForEach(participants) { participant in
                                                if let entry = round.entries.first(where: { $0.participantID == participant.id }) {
                                                    roundEntryText(entry)
                                                } else {
                                                    Text("—").font(.bodySmall).foregroundStyle(.textTertiary)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(Space.lg)
                    }
                }
            }
            .navigationTitle("Manches précédentes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    /// `12 → 24` quand une règle a modifié la valeur saisie (doublement Skyjo, bonus…) — même
    /// affichage que `ResultsView.roundEntryText`.
    private func roundEntryText(_ entry: ScoreEntry) -> some View {
        Text(entry.rawValue == entry.computedValue ? "\(entry.computedValue)" : "\(entry.rawValue) → \(entry.computedValue)")
            .font(.bodySmall)
            .foregroundStyle(.textPrimary)
    }
}
