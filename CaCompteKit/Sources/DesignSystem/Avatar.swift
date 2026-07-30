import Foundation

/// Doc 08 « Avatars » — trois sources, toutes hors ligne.
public struct Avatar: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case symbol(String)
        case emoji(String)
        case photo(Data)
    }

    public let kind: Kind
    public let palette: PlayerPalette

    public init(kind: Kind, palette: PlayerPalette) {
        self.kind = kind
        self.palette = palette
    }

    /// Sélection curatée d'emoji (animaux, objets, expressions) — seule source d'avatar par
    /// défaut désormais : pas de symbole à choisir, l'emoji vient du hachage du pseudo.
    public static let curatedEmoji: [String] = [
        "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮", "🐷", "🐸", "🐵",
        "🐔", "🐧", "🐦", "🦆", "🦉", "🦇", "🐺", "🐗", "🐴", "🦄",
        "🐝", "🦋", "🐢", "🐍", "🦎", "🐙", "🦑", "🦀", "🐠", "🐬",
        "🐳", "🦈", "🐌", "🐞", "🦔", "🦥", "🦦", "🦨", "🦡",
        "🎨", "🎮", "🎸", "🚀", "⚽️", "🏀", "🎯", "🎲", "🍕", "🌈",
        "⭐️", "🔥", "💎", "🍀", "🎈",
        "🤖", "👾", "🧙", "🥷", "🏎️", "🌸",
        "🦝", "🐲", "🍄", "⚡", "♥️", "💚", "💙", "🩷",
    ]

    /// Doc 08 : « un joueur créé sans choix reçoit un symbole et une couleur dérivés du hachage
    /// stable de son pseudo » — ici toujours un emoji, jamais un choix manuel. `String.hashValue`
    /// est salé aléatoirement par processus — inutile ici — d'où un FNV-1a manuel, trivialement
    /// portable en Kotlin pour produire le même résultat sur les deux plateformes.
    public static func generated(for nickname: String) -> Avatar {
        let hash = fnv1a(nickname)
        let paletteIndex = Int(hash % 10) + 1
        let emojiIndex = Int((hash / 10) % UInt64(curatedEmoji.count))
        return Avatar(kind: .emoji(curatedEmoji[emojiIndex]), palette: PlayerPalette(index: paletteIndex))
    }

    private static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
