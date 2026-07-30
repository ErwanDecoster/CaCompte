import SwiftUI

#Preview("Composants — clair") {
    ComponentGallery()
}

#Preview("Composants — sombre") {
    ComponentGallery()
        .preferredColorScheme(.dark)
}

#Preview("Composants — AX5") {
    ComponentGallery()
        .dynamicTypeSize(.accessibility5)
}

private struct ComponentGallery: View {
    @State private var isChipSelected = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Card {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("Skyjo · Manche 4").font(.h5)
                        Text("4 joueurs").font(.bodySmall).foregroundStyle(.textSecondary)
                    }
                }

                HStack(spacing: Space.sm) {
                    Chip("Skyjo", isSelected: isChipSelected) { isChipSelected.toggle() }
                    Chip("Yams", isSelected: !isChipSelected) { isChipSelected.toggle() }
                }

                Banner("Partie sauvegardée", actionTitle: "Annuler") {}

                EmptyState(
                    icon: "tray",
                    message: "Aucune partie. Commencer une partie",
                    actionTitle: "Commencer une partie"
                ) {}
            }
            .padding(Space.lg)
        }
        .background(.neutralBg)
    }
}
