import SwiftUI

/// Charte graphique §5.5 — sélectionné : fond `brand/ink` à 12 %, jamais la couleur seule
/// (le libellé et la bordure doublent l'état sélectionné, §13).
public struct Chip: View {
    private let title: LocalizedStringResource
    private let isSelected: Bool
    private let action: () -> Void

    public init(_ title: LocalizedStringResource, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.label)
                .foregroundStyle(isSelected ? .brandInk : .textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(
                    isSelected ? Color.brandInk.opacity(0.12) : Color.neutralFill,
                    in: .rect(cornerRadius: Radius.sm)
                )
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .strokeBorder(.brandInk, lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
