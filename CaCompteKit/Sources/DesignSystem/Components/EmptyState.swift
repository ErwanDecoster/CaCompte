import SwiftUI

/// Charte graphique §12.2 — un constat + une action. L'illustration dessinée (trait 2 px +
/// aplat `brand/brass`, §10) n'existe pas encore : un SF Symbol tient sa place en attendant
/// (voir README « Actions manuelles en attente »).
public struct EmptyState: View {
    private let icon: String
    private let message: LocalizedStringResource
    private let actionTitle: LocalizedStringResource?
    private let action: (() -> Void)?

    public init(
        icon: String,
        message: LocalizedStringResource,
        actionTitle: LocalizedStringResource? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Space.lg) {
            Image(systemName: icon)
                .font(.system(size: IconSize.xl))
                .foregroundStyle(.textTertiary)
            Text(message)
                .font(.bodyText)
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.primary(size: .medium))
            }
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 160)
    }
}
