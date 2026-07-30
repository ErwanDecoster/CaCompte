import SwiftUI

/// Charte graphique §5.3 — action principale d'un écran (une seule à la fois). Le libellé est
/// blanc en clair, `neutral/bg` en sombre (jamais blanc pur, qui vibrerait sur `brand/ink` clair).
public struct PrimaryButtonStyle: ButtonStyle {
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
        @Environment(\.colorScheme) private var colorScheme

        public var body: some View {
            configuration.label
                .font(.button)
                .opacity(isLoading ? 0 : 1)
                .overlay {
                    if isLoading {
                        ProgressView().tint(labelColor)
                    }
                }
                .foregroundStyle(labelColor)
                .frame(maxWidth: .infinity)
                .frame(height: size.height)
                .padding(.horizontal, size.horizontalPadding)
                .background(backgroundColor, in: .rect(cornerRadius: Radius.md))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.linear(duration: 0.12), value: configuration.isPressed)
                .allowsHitTesting(!isLoading)
        }

        private var backgroundColor: Color {
            guard isEnabled else { return .neutralFill }
            return configuration.isPressed ? .brandInkPressed : .brandInk
        }

        private var labelColor: Color {
            guard isEnabled else { return .textDisabled }
            return colorScheme == .dark ? .neutralBg : .white
        }
    }
}

public extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func primary(size: ButtonSize = .large, isLoading: Bool = false) -> PrimaryButtonStyle {
        PrimaryButtonStyle(size: size, isLoading: isLoading)
    }
}
