import SwiftUI
import Charts

/// Charte graphique §1.5 — dix teintes, dont les six premières restent mutuellement
/// distinguables en deutéranopie et en protanopie. La couleur n'est jamais le seul porteur
/// d'information : chaque joueur reçoit aussi son symbole de série, utilisé sur la courbe
/// d'évolution (doc 08 « Couleurs des joueurs »).
public struct PlayerPalette: Sendable, Hashable {
    public let index: Int
    public let color: Color
    public let chartSymbol: BasicChartSymbolShape
    public let accessibilityName: LocalizedStringResource

    public init(index: Int) {
        precondition((1...10).contains(index), "player index must be in 1...10")
        self.index = index
        self.color = .player(index)
        self.chartSymbol = Self.chartSymbols[index - 1]
        self.accessibilityName = Self.names[index - 1]
    }

    public static func == (lhs: PlayerPalette, rhs: PlayerPalette) -> Bool {
        lhs.index == rhs.index
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(index)
    }

    /// `BasicChartSymbolShape` n'a que 8 formes natives ; la charte en demande 10 (§1.5 : étoile,
    /// hexagone). #6 et #9 sont donc des substitutions (astérisque, carré) qui restent uniques
    /// parmi les six premiers joueurs — la seule garantie exigée par la charte. À revoir si un
    /// symbole custom devient nécessaire (voir README « Actions manuelles en attente »).
    private static let chartSymbols: [BasicChartSymbolShape] = [
        .circle, .square, .triangle, .diamond, .cross, .asterisk, .triangle, .pentagon, .square, .plus,
    ]

    private static let names: [LocalizedStringResource] = [
        "Azur", "Ambre", "Émeraude", "Magenta", "Ardoise", "Cyan", "Vermillon", "Violet", "Olive", "Rose",
    ]
}
