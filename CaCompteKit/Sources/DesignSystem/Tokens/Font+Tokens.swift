import SwiftUI

/// Charte graphique §2.2 — chaque token référence un style système, jamais une taille en
/// points : le tracking et l'*optical sizing* de SF Pro s'appliquent seuls, Dynamic Type opère
/// sans intervention.
public extension Font {
    static var h1: Font { .largeTitle.weight(.bold) }
    static var h2: Font { .title.weight(.bold) }
    static var h3: Font { .title2.weight(.bold) }
    static var h4: Font { .title3.weight(.semibold) }
    static var h5: Font { .headline }
    static var h6: Font { .subheadline.weight(.semibold) }
    static var bodyText: Font { .body }
    static var bodySmall: Font { .callout }
    static var label: Font { .footnote.weight(.medium) }
    static var captionText: Font { .caption }
    static var caption2Text: Font { .caption2 }
    static var button: Font { .headline }

    /// Charte graphique §2.3 — chiffres de score : chasse fixe (`monospacedDigit`) et dessin
    /// `.rounded`, seul écart typographique assumé de la charte.
    static var scoreXL: Font { .system(.largeTitle, design: .rounded, weight: .semibold).monospacedDigit() }
    static var scoreL: Font { .system(.title2, design: .rounded, weight: .semibold).monospacedDigit() }
    static var scoreM: Font { .system(.body, design: .rounded, weight: .medium).monospacedDigit() }
}
