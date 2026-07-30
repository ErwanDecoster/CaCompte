import SwiftUI

/// Charte graphique §5.3 — action secondaire : fond transparent, bordure 1,5 pt.
public struct SecondaryButtonStyle: ButtonStyle {
    private let size: ButtonSize
    private let isLoading: Bool

    public init(size: ButtonSize = .large, isLoading: Bool = false) {
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
                .frame(maxWidth: .infinity)
                .frame(height: size.height)
                .padding(.horizontal, size.horizontalPadding)
                .background(backgroundColor, in: .rect(cornerRadius: Radius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.md)
                        .strokeBorder(borderColor, lineWidth: 1.5)
                }
                .allowsHitTesting(!isLoading)
        }

        private var backgroundColor: Color {
            guard isEnabled else { return .clear }
            return configuration.isPressed ? Color.brandInk.opacity(0.08) : .clear
        }

        private var borderColor: Color {
            guard isEnabled else { return .neutralBorder }
            return configuration.isPressed ? .brandInk : .neutralBorderStrong
        }
    }
}

public extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static func secondary(size: ButtonSize = .large, isLoading: Bool = false) -> SecondaryButtonStyle {
        SecondaryButtonStyle(size: size, isLoading: isLoading)
    }
}
