import SwiftUI

/// Charte graphique §5.5 — bandeau flottant (toast) : `elev/3`, une action maximum.
/// L'auto-disparition (4 s, 8 s avec action) est une responsabilité de l'appelant, pas de la vue.
public struct Banner: View {
    private let message: LocalizedStringResource
    private let actionTitle: LocalizedStringResource?
    private let action: (() -> Void)?

    public init(
        _ message: LocalizedStringResource,
        actionTitle: LocalizedStringResource? = nil,
        action: (() -> Void)? = nil
    ) {
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(spacing: Space.md) {
            Text(message)
                .font(.bodySmall)
                .foregroundStyle(.textPrimary)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.label)
                    .foregroundStyle(.brandInk)
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .frame(minHeight: 48)
        .background(.regularMaterial, in: .rect(cornerRadius: Radius.lg))
    }
}
