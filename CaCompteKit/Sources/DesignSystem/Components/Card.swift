import SwiftUI

/// Charte graphique §5.5 — `elev/1`, sans ombre. Bordure `neutral/border` en sombre uniquement :
/// sans elle, la surface ne se détache pas assez du fond (§8).
public struct Card<Content: View>: View {
    /// Gouttière recommandée entre deux cartes (§5.5).
    public static var gutter: CGFloat { 12 }

    @Environment(\.colorScheme) private var colorScheme
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(Space.lg)
            .background(.neutralSurface, in: .rect(cornerRadius: Radius.md))
            .overlay {
                if colorScheme == .dark {
                    RoundedRectangle(cornerRadius: Radius.md)
                        .strokeBorder(.neutralBorder, lineWidth: 1)
                }
            }
    }
}
