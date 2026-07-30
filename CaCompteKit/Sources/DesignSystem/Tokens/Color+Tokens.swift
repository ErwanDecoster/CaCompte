import SwiftUI

/// Charte graphique §14 — traduction mécanique du tableau de synthèse des couleurs. Chaque
/// entrée référence le catalogue d'assets (variantes Any/Dark), jamais une valeur littérale.
public extension ShapeStyle where Self == Color {
    static var brandInk: Color { Color("brand/ink", bundle: .designSystem) }
    static var brandInkPressed: Color { Color("brand/inkPressed", bundle: .designSystem) }
    static var brandBrass: Color { Color("brand/brass", bundle: .designSystem) }
    static var brandTeal: Color { Color("brand/teal", bundle: .designSystem) }

    static var neutralBg: Color { Color("neutral/bg", bundle: .designSystem) }
    static var neutralSurface: Color { Color("neutral/surface", bundle: .designSystem) }
    static var neutralSunken: Color { Color("neutral/sunken", bundle: .designSystem) }
    static var neutralFill: Color { Color("neutral/fill", bundle: .designSystem) }
    static var neutralBorder: Color { Color("neutral/border", bundle: .designSystem) }
    static var neutralBorderStrong: Color { Color("neutral/borderStrong", bundle: .designSystem) }

    static var textPrimary: Color { Color("text/primary", bundle: .designSystem) }
    static var textSecondary: Color { Color("text/secondary", bundle: .designSystem) }
    static var textTertiary: Color { Color("text/tertiary", bundle: .designSystem) }
    static var textDisabled: Color { Color("text/disabled", bundle: .designSystem) }

    static var semanticSuccess: Color { Color("semantic/success", bundle: .designSystem) }
    static var semanticError: Color { Color("semantic/error", bundle: .designSystem) }
    static var semanticWarning: Color { Color("semantic/warning", bundle: .designSystem) }
    static var semanticInfo: Color { Color("semantic/info", bundle: .designSystem) }
}

public extension Color {
    /// Charte graphique §1.5 — palette des joueurs, `index` de 1 à 10. `PlayerPalette` est le
    /// point d'entrée à préférer : la couleur seule ne porte jamais l'information (§1.5, §13.1).
    static func player(_ index: Int) -> Color {
        precondition((1...10).contains(index), "player index must be in 1...10")
        return Color("player/\(index)", bundle: .designSystem)
    }
}
