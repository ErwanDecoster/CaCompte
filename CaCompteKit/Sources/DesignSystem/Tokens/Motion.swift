/// Charte graphique §9.1. Rien entre `screen` et `celebrate` : l'entre-deux paraît lent sans
/// paraître intentionnel. `celebrate` est réservé à l'écran de résultats (§9.2).
public enum Motion {
    public static let instant = Duration.milliseconds(0)
    public static let fast = Duration.milliseconds(120)
    public static let micro = Duration.milliseconds(180)
    public static let standard = Duration.milliseconds(280)
    public static let screen = Duration.milliseconds(350)
    public static let celebrate = Duration.milliseconds(650)
}
