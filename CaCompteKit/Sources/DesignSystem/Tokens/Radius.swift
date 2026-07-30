import CoreGraphics

/// Charte graphique §5.1 — coins concentriques : un élément imbriqué utilise
/// `rayon_parent − padding`, jamais une valeur fixe (voir `.rect(corners: .concentric)`).
public enum Radius {
    public static let xs: CGFloat = 6
    public static let sm: CGFloat = 10
    public static let md: CGFloat = 14
    public static let lg: CGFloat = 20
    public static let xl: CGFloat = 28
    public static let full: CGFloat = 999
}
