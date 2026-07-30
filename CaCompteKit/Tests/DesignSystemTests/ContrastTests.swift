import Testing
import UIKit
@testable import DesignSystem

/// Charte graphique §1.1 : « Vérifier le contraste par calcul, pas à l'œil. » Ce test rejoue
/// la formule WCAG 2.1 (luminance relative sRGB) sur le catalogue d'assets réel — pas sur une
/// copie des valeurs — pour les paires dont la charte donne un ratio explicite (§1.3, §1.4,
/// §1.5, §5.3). Ce n'est pas les 68 paires de la vérification originale (le détail complet
/// n'est pas dans les docs), mais toute paire dont le texte donne un chiffre est couverte : une
/// couleur modifiée dans Xcode sans mise à jour de la charte fait échouer ce test.
@Suite("Contrastes WCAG — charte §1")
struct ContrastTests {
    enum ColorSource: Sendable {
        case token(String)
        case white

        func resolve(style: UIUserInterfaceStyle) -> UIColor {
            let trait = UITraitCollection(userInterfaceStyle: style)
            switch self {
            case .white:
                return UIColor.white.resolvedColor(with: trait)
            case .token(let name):
                guard let color = UIColor(named: name, in: Bundle.designSystem, compatibleWith: trait) else {
                    Issue.record("Token manquant dans le catalogue d'assets : \(name)")
                    return .clear
                }
                return color.resolvedColor(with: trait)
            }
        }
    }

    struct Case: Sendable, CustomStringConvertible {
        let label: String
        let foreground: ColorSource
        let background: ColorSource
        let style: UIUserInterfaceStyle
        let expectedRatio: Double
        let minimumRequired: Double

        var description: String { label }
    }

    static let cases: [Case] = [
        // Clair — §1.3, §1.4, §1.5
        Case(label: "neutral/borderStrong / neutral/surface (clair)", foreground: .token("neutral/borderStrong"), background: .token("neutral/surface"), style: .light, expectedRatio: 3.61, minimumRequired: 3.0),
        Case(label: "text/primary / neutral/surface (clair)", foreground: .token("text/primary"), background: .token("neutral/surface"), style: .light, expectedRatio: 17.26, minimumRequired: 4.5),
        Case(label: "text/secondary / neutral/surface (clair)", foreground: .token("text/secondary"), background: .token("neutral/surface"), style: .light, expectedRatio: 7.87, minimumRequired: 4.5),
        Case(label: "text/tertiary / neutral/surface (clair)", foreground: .token("text/tertiary"), background: .token("neutral/surface"), style: .light, expectedRatio: 6.06, minimumRequired: 4.5),
        Case(label: "text/tertiary / neutral/fill (clair)", foreground: .token("text/tertiary"), background: .token("neutral/fill"), style: .light, expectedRatio: 4.84, minimumRequired: 4.5),
        Case(label: "semantic/success / neutral/surface (clair)", foreground: .token("semantic/success"), background: .token("neutral/surface"), style: .light, expectedRatio: 6.55, minimumRequired: 4.5),
        Case(label: "semantic/error / neutral/surface (clair)", foreground: .token("semantic/error"), background: .token("neutral/surface"), style: .light, expectedRatio: 6.17, minimumRequired: 4.5),
        Case(label: "semantic/warning / neutral/surface (clair)", foreground: .token("semantic/warning"), background: .token("neutral/surface"), style: .light, expectedRatio: 6.33, minimumRequired: 4.5),
        Case(label: "semantic/info / neutral/surface (clair)", foreground: .token("semantic/info"), background: .token("neutral/surface"), style: .light, expectedRatio: 6.49, minimumRequired: 4.5),
        Case(label: "player/1 / neutral/surface (clair)", foreground: .token("player/1"), background: .token("neutral/surface"), style: .light, expectedRatio: 4.83, minimumRequired: 3.0),
        Case(label: "player/2 / neutral/surface (clair)", foreground: .token("player/2"), background: .token("neutral/surface"), style: .light, expectedRatio: 3.28, minimumRequired: 3.0),
        Case(label: "player/3 / neutral/surface (clair)", foreground: .token("player/3"), background: .token("neutral/surface"), style: .light, expectedRatio: 3.23, minimumRequired: 3.0),
        Case(label: "player/4 / neutral/surface (clair)", foreground: .token("player/4"), background: .token("neutral/surface"), style: .light, expectedRatio: 5.15, minimumRequired: 3.0),
        Case(label: "player/5 / neutral/surface (clair)", foreground: .token("player/5"), background: .token("neutral/surface"), style: .light, expectedRatio: 7.53, minimumRequired: 3.0),
        Case(label: "player/6 / neutral/surface (clair)", foreground: .token("player/6"), background: .token("neutral/surface"), style: .light, expectedRatio: 3.14, minimumRequired: 3.0),
        Case(label: "player/7 / neutral/surface (clair)", foreground: .token("player/7"), background: .token("neutral/surface"), style: .light, expectedRatio: 3.77, minimumRequired: 3.0),
        Case(label: "player/8 / neutral/surface (clair)", foreground: .token("player/8"), background: .token("neutral/surface"), style: .light, expectedRatio: 6.24, minimumRequired: 3.0),
        Case(label: "player/9 / neutral/surface (clair)", foreground: .token("player/9"), background: .token("neutral/surface"), style: .light, expectedRatio: 3.88, minimumRequired: 3.0),
        Case(label: "player/10 / neutral/surface (clair)", foreground: .token("player/10"), background: .token("neutral/surface"), style: .light, expectedRatio: 3.80, minimumRequired: 3.0),
        Case(label: "libellé blanc / brand/ink — bouton primaire (clair)", foreground: .white, background: .token("brand/ink"), style: .light, expectedRatio: 8.59, minimumRequired: 4.5),

        // Sombre — §1.3, §1.4, §1.5
        Case(label: "neutral/borderStrong / neutral/surface (sombre)", foreground: .token("neutral/borderStrong"), background: .token("neutral/surface"), style: .dark, expectedRatio: 3.74, minimumRequired: 3.0),
        Case(label: "text/primary / neutral/surface (sombre)", foreground: .token("text/primary"), background: .token("neutral/surface"), style: .dark, expectedRatio: 15.56, minimumRequired: 4.5),
        Case(label: "text/secondary / neutral/surface (sombre)", foreground: .token("text/secondary"), background: .token("neutral/surface"), style: .dark, expectedRatio: 9.92, minimumRequired: 4.5),
        Case(label: "text/tertiary / neutral/surface (sombre)", foreground: .token("text/tertiary"), background: .token("neutral/surface"), style: .dark, expectedRatio: 6.91, minimumRequired: 4.5),
        Case(label: "semantic/success / neutral/surface (sombre)", foreground: .token("semantic/success"), background: .token("neutral/surface"), style: .dark, expectedRatio: 8.86, minimumRequired: 4.5),
        Case(label: "semantic/error / neutral/surface (sombre)", foreground: .token("semantic/error"), background: .token("neutral/surface"), style: .dark, expectedRatio: 7.76, minimumRequired: 4.5),
        Case(label: "semantic/warning / neutral/surface (sombre)", foreground: .token("semantic/warning"), background: .token("neutral/surface"), style: .dark, expectedRatio: 11.05, minimumRequired: 4.5),
        Case(label: "semantic/info / neutral/surface (sombre)", foreground: .token("semantic/info"), background: .token("neutral/surface"), style: .dark, expectedRatio: 8.33, minimumRequired: 4.5),
        Case(label: "player/1 / neutral/surface (sombre)", foreground: .token("player/1"), background: .token("neutral/surface"), style: .dark, expectedRatio: 6.48, minimumRequired: 3.0),
        Case(label: "player/2 / neutral/surface (sombre)", foreground: .token("player/2"), background: .token("neutral/surface"), style: .dark, expectedRatio: 9.16, minimumRequired: 3.0),
        Case(label: "player/3 / neutral/surface (sombre)", foreground: .token("player/3"), background: .token("neutral/surface"), style: .dark, expectedRatio: 13.23, minimumRequired: 3.0),
        Case(label: "player/4 / neutral/surface (sombre)", foreground: .token("player/4"), background: .token("neutral/surface"), style: .dark, expectedRatio: 6.33, minimumRequired: 3.0),
        Case(label: "player/5 / neutral/surface (sombre)", foreground: .token("player/5"), background: .token("neutral/surface"), style: .dark, expectedRatio: 6.97, minimumRequired: 3.0),
        Case(label: "player/6 / neutral/surface (sombre)", foreground: .token("player/6"), background: .token("neutral/surface"), style: .dark, expectedRatio: 11.88, minimumRequired: 3.0),
        Case(label: "player/7 / neutral/surface (sombre)", foreground: .token("player/7"), background: .token("neutral/surface"), style: .dark, expectedRatio: 6.93, minimumRequired: 3.0),
        Case(label: "player/8 / neutral/surface (sombre)", foreground: .token("player/8"), background: .token("neutral/surface"), style: .dark, expectedRatio: 6.83, minimumRequired: 3.0),
        Case(label: "player/9 / neutral/surface (sombre)", foreground: .token("player/9"), background: .token("neutral/surface"), style: .dark, expectedRatio: 15.37, minimumRequired: 3.0),
        Case(label: "player/10 / neutral/surface (sombre)", foreground: .token("player/10"), background: .token("neutral/surface"), style: .dark, expectedRatio: 7.33, minimumRequired: 3.0),
        Case(label: "libellé neutral/bg / brand/ink — bouton primaire (sombre)", foreground: .token("neutral/bg"), background: .token("brand/ink"), style: .dark, expectedRatio: 9.18, minimumRequired: 4.5),
    ]

    @Test("Paire respecte le ratio documenté dans la charte §1", arguments: cases)
    func pairMatchesDocumentedRatio(_ testCase: Case) {
        let foreground = testCase.foreground.resolve(style: testCase.style)
        let background = testCase.background.resolve(style: testCase.style)
        let ratio = contrastRatio(foreground, background)

        #expect(ratio >= testCase.minimumRequired, "\(testCase.label) : \(ratio) sous le seuil WCAG \(testCase.minimumRequired)")
        #expect(
            abs(ratio - testCase.expectedRatio) < 0.05,
            "\(testCase.label) : \(ratio) ≠ \(testCase.expectedRatio) documenté — couleur modifiée sans mise à jour de la charte"
        )
    }
}

private func luminanceComponent(_ value: CGFloat) -> Double {
    let c = Double(value)
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
}

private func relativeLuminance(_ color: UIColor) -> Double {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    return 0.2126 * luminanceComponent(r) + 0.7152 * luminanceComponent(g) + 0.0722 * luminanceComponent(b)
}

private func contrastRatio(_ a: UIColor, _ b: UIColor) -> Double {
    let l1 = relativeLuminance(a)
    let l2 = relativeLuminance(b)
    return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
}
