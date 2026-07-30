import DesignSystem
import Foundation
import Store

/// Même pont que `PlayerRecord+Avatar.swift`, côté snapshot de partie. Doc 03 ne conserve pas
/// de photo dans `ParticipantRecord` (seuls `avatarKindSnapshot`/`avatarValueSnapshot` sont des
/// chaînes) : un avatar photo retombe sur un symbole générique dans les écrans de résultats.
extension ParticipantRecord {
    var palette: PlayerPalette {
        PlayerPalette(index: Int(paletteIDSnapshot) ?? 1)
    }

    var avatar: Avatar {
        let kind: Avatar.Kind
        switch avatarKindSnapshot {
        case "emoji":
            kind = .emoji(avatarValueSnapshot)
        case "photo":
            kind = .symbol("person.fill")
        default:
            kind = .symbol(avatarValueSnapshot.isEmpty ? "person.fill" : avatarValueSnapshot)
        }
        return Avatar(kind: kind, palette: palette)
    }
}
