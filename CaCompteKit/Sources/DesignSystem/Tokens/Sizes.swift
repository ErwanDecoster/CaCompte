import CoreGraphics

/// Charte graphique §4 — tailles d'affichage des icônes. Rien sous `icon/sm` (16 pt) : en
/// dessous, un trait de 1,75 px sur grille 24 tombe sous le pixel physique en @2x.
public enum IconSize {
    public static let sm: CGFloat = 16
    public static let md: CGFloat = 20
    public static let base: CGFloat = 24
    public static let lg: CGFloat = 28
    public static let xl: CGFloat = 32
}

/// Charte graphique §6 — la zone tactile est découplée du visuel : on agrandit la cible,
/// jamais le dessin (`.contentShape(.rect)`).
public enum Touch {
    public static let minimum: CGFloat = 44
    public static let gap: CGFloat = 8
}

/// Charte graphique §5.3 — hauteurs de bouton, zone tactile étendue à `Touch.minimum` pour
/// `small`.
public enum ButtonHeight {
    public static let large: CGFloat = 52
    public static let medium: CGFloat = 44
    public static let small: CGFloat = 32
}

/// Charte graphique §6 — touches du pavé numérique, au-delà du minimum tactile : on tape à
/// bout de bras, autour d'une table.
public enum Keypad {
    public static let key: CGFloat = 56
    public static let gap: CGFloat = 12
}
