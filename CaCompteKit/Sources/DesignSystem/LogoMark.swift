import SwiftUI

/// Charte graphique §11.1 — la barre de comptage : quatre traits verticaux barrés d'un
/// cinquième en diagonale, sur une grille de 24 unités. Résolution indépendante : sert aussi
/// bien à l'icône seule (§11.2) qu'à la génération de l'icône d'app (§11.5).
public struct LogoMark: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let originX = rect.minX + (rect.width - 24 * scale) / 2
        let originY = rect.minY + (rect.height - 24 * scale) / 2

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * scale, y: originY + y * scale)
        }

        let barWidth: CGFloat = 2
        let barHeight: CGFloat = 16
        let gap: CGFloat = 3
        let groupWidth = 4 * barWidth + 3 * gap // 17 u
        let leftMargin = (24 - groupWidth) / 2 // 3.5 u
        let top = (24 - barHeight) / 2 // 4 u
        let bottom = top + barHeight // 20 u

        var path = Path()

        for i in 0..<4 {
            let x = leftMargin + CGFloat(i) * (barWidth + gap) + barWidth / 2
            path.move(to: point(x, top))
            path.addLine(to: point(x, bottom))
        }

        // Diagonale à 22°, débordant de 1,5 u au-delà du groupe de chaque côté.
        let angle = 22 * CGFloat.pi / 180
        let halfSpan = groupWidth / 2 + 1.5
        let rise = halfSpan * tan(angle)
        let centerX = leftMargin + groupWidth / 2
        let centerY: CGFloat = 12
        path.move(to: point(centerX - halfSpan, centerY + rise))
        path.addLine(to: point(centerX + halfSpan, centerY - rise))

        return path
    }

    /// Épaisseur 2 u sur la grille 24, extrémités arrondies de rayon 1 u — exactement la moitié
    /// de l'épaisseur, d'où `.round` plutôt qu'un rayon calculé séparément.
    public static func strokeStyle(gridSize: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: gridSize / 12, lineCap: .round, lineJoin: .round)
    }
}

/// Charte graphique §11.2 — déclinaison « icône seule », marque dans un carré à 60 % de la
/// largeur.
public struct LogoMarkView: View {
    private let color: Color

    public init(color: Color = .brandInk) {
        self.color = color
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height) * 0.6
            LogoMark()
                .stroke(color, style: LogoMark.strokeStyle(gridSize: size))
                .frame(width: size, height: size)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
