import Foundation
import SwiftData

/// Doc 03 « ParticipantRecord » — un joueur **dans une partie donnée**. Le *snapshot* est
/// essentiel : si la fiche joueur est renommée ou supprimée après coup, l'historique de cette
/// partie doit rester inchangé — d'où `player` optionnel (règle `.nullify`) et les champs
/// `*Snapshot` figés à la création.
@Model
public final class ParticipantRecord {
    public var id: UUID = UUID()
    public var player: PlayerRecord?
    public var nicknameSnapshot: String = ""
    public var avatarKindSnapshot: String = "symbol"
    public var avatarValueSnapshot: String = ""
    public var paletteIDSnapshot: String = "1"
    public var seatIndex: Int = 0
    /// Doc 05 « Belote » — `nil` pour tous les jeux individuels (voir `Domain.Participant.teamID`).
    public var teamID: String?
    public var finalRank: Int?
    public var finalScore: Int?
    public var match: MatchRecord?

    public init(
        id: UUID = UUID(),
        player: PlayerRecord?,
        nicknameSnapshot: String,
        avatarKindSnapshot: String,
        avatarValueSnapshot: String,
        paletteIDSnapshot: String,
        seatIndex: Int,
        teamID: String? = nil,
        finalRank: Int? = nil,
        finalScore: Int? = nil
    ) {
        self.id = id
        self.player = player
        self.nicknameSnapshot = nicknameSnapshot
        self.avatarKindSnapshot = avatarKindSnapshot
        self.avatarValueSnapshot = avatarValueSnapshot
        self.paletteIDSnapshot = paletteIDSnapshot
        self.seatIndex = seatIndex
        self.teamID = teamID
        self.finalRank = finalRank
        self.finalScore = finalScore
    }
}
