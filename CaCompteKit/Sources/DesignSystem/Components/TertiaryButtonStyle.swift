import SwiftUI

/// Charte graphique §5.3 — action tertiaire (texte) : libellé seul, sans fond au repos.
public struct TertiaryButtonStyle: ButtonStyle {
    private let size: ButtonSize
    private let isLoading: Bool

    public init(size: ButtonSize = .medium, isLoading: Bool = false) {
        self.size = size
        self.isLoading = isLoading
    }

    public func makeBody(configuration: Configuration) -> some View {
        Rendered(configuration: configuration, size: size, isLoading: isLoading)
    }

    public struct Rendered: View {
        let configuration: Configuration
        let size: ButtonSize
        let isLoading: Bool

        @Environment(\.isEnabled) private var isEnabled

        public var body: some View {
            configuration.label
                .font(.button)
                .opacity(isLoading ? 0 : 1)
                .overlay {
                    if isLoading {
                        ProgressView().tint(.brandInk)
                    }
                }
                .foregroundStyle(isEnabled ? .brandInk : .textDisabled)
                .frame(height: size.height)
                .padding(.horizontal, size.horizontalPadding)
                .background(backgroundColor, in: .rect(cornerRadius: Radius.sm))
                .allowsHitTesting(!isLoading)
        }

        private var backgroundColor: Color {
            guard isEnabled, configuration.isPressed else { return .clear }
            return Color.brandInk.opacity(0.08)
        }
    }
}

public extension ButtonStyle where Self == TertiaryButtonStyle {
    static var tertiary: TertiaryButtonStyle { TertiaryButtonStyle() }
    static func tertiary(size: ButtonSize = .medium, isLoading: Bool = false) -> TertiaryButtonStyle {
        TertiaryButtonStyle(size: size, isLoading: isLoading)
    }
}
