import SwiftUI

/// Charte graphique §11.2 — wordmark « Ça Compte » en Outfit SemiBold, tracking −1 %.
/// Vectorisé au build de la police (Google Fonts, licence SIL OFL — voir `Licenses/Outfit-OFL.txt`
/// à la racine du repo) : la police elle-même n'est pas embarquée dans l'app, seul le tracé de
/// ces neuf caractères l'est, en SVG dans le catalogue d'assets (`logo/wordmark`).
public struct LogoWordmark: View {
    private let color: Color

    public init(color: Color = .brandInk) {
        self.color = color
    }

    public var body: some View {
        Image("logo/wordmark", bundle: .designSystem)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .accessibilityLabel("Ça Compte")
    }
}

/// Charte graphique §11.2 — icône + wordmark, séparés de 2× l'épaisseur de trait de l'icône.
public struct LogoLockupHorizontal: View {
    private let color: Color
    private let height: CGFloat

    public init(color: Color = .brandInk, height: CGFloat = 32) {
        self.color = color
        self.height = height
    }

    public var body: some View {
        let strokeWidth = height / 12
        HStack(spacing: strokeWidth * 2) {
            LogoMark()
                .stroke(color, style: LogoMark.strokeStyle(gridSize: height))
                .frame(width: height, height: height)
            LogoWordmark(color: color)
                .frame(height: height)
        }
        .padding(strokeWidth * 2)
        .accessibilityElement(children: .combine)
    }
}

/// Charte graphique §11.2 — icône au-dessus du wordmark, centrés, séparés de 3× l'épaisseur.
public struct LogoLockupVertical: View {
    private let color: Color
    private let height: CGFloat

    public init(color: Color = .brandInk, height: CGFloat = 32) {
        self.color = color
        self.height = height
    }

    public var body: some View {
        let strokeWidth = height / 12
        VStack(spacing: strokeWidth * 3) {
            LogoMark()
                .stroke(color, style: LogoMark.strokeStyle(gridSize: height))
                .frame(width: height, height: height)
            LogoWordmark(color: color)
                .frame(height: height)
        }
        .padding(strokeWidth * 2)
        .accessibilityElement(children: .combine)
    }
}
