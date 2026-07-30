import SwiftUI

// Le contraste augmenté se bascule depuis les variantes du canvas Xcode (icône ⧉), pas ici :
// `\.colorSchemeContrast` n'est pas key-path assignable sur toutes les plateformes du package.

#Preview("Boutons — clair") {
    ButtonGallery()
}

#Preview("Boutons — sombre") {
    ButtonGallery()
        .preferredColorScheme(.dark)
}

#Preview("Boutons — AX5") {
    ButtonGallery()
        .dynamicTypeSize(.accessibility5)
}

private struct ButtonGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                group("Primaire") {
                    Button("Valider la manche") {}
                        .buttonStyle(.primary)
                    Button("Valider la manche") {}
                        .buttonStyle(.primary)
                        .disabled(true)
                    Button("Valider la manche") {}
                        .buttonStyle(.primary(isLoading: true))
                }
                group("Secondaire") {
                    Button("Annuler") {}
                        .buttonStyle(.secondary)
                    Button("Annuler") {}
                        .buttonStyle(.secondary)
                        .disabled(true)
                }
                group("Tertiaire") {
                    Button("Modifier") {}
                        .buttonStyle(.tertiary)
                    Button("Modifier") {}
                        .buttonStyle(.tertiary)
                        .disabled(true)
                }
            }
            .padding(Space.lg)
        }
        .background(.neutralBg)
    }

    @ViewBuilder
    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title).font(.h6).foregroundStyle(.textSecondary)
            content()
        }
    }
}
