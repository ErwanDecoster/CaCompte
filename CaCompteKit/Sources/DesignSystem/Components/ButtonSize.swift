import CoreGraphics

/// Charte graphique §5.3 — hauteurs de bouton, communes aux trois styles.
public enum ButtonSize: Sendable {
    case large, medium, small

    public var height: CGFloat {
        switch self {
        case .large: ButtonHeight.large
        case .medium: ButtonHeight.medium
        case .small: ButtonHeight.small
        }
    }

    /// §3.3 ne documente le padding horizontal que pour `large` (24) et `medium` (16) ;
    /// `small` réutilise la valeur `medium`, faute de spécification dédiée.
    public var horizontalPadding: CGFloat {
        switch self {
        case .large: 24
        case .medium, .small: 16
        }
    }
}
