import Foundation
import SwiftData

/// Modèle de données §« PlayerRecord » — la fiche joueur, réutilisée d'une partie à l'autre.
/// Toute propriété a une valeur par défaut : contrainte CloudKit, pas une préférence de style.
@Model
public final class PlayerRecord {
    public var id: UUID = UUID()
    public var nickname: String = ""
    /// `"symbol"` | `"emoji"` | `"photo"`
    public var avatarKind: String = "symbol"
    /// Nom SF Symbol, ou emoji, ou `""` si `avatarKind == "photo"`.
    public var avatarValue: String = ""
    @Attribute(.externalStorage) public var avatarPhoto: Data?
    /// Identifiant de palette joueur, `"1"`…`"10"` (charte §1.5).
    public var paletteID: String = "1"
    public var createdAt: Date = Date()
    public var isArchived: Bool = false
    public var sortIndex: Int = 0

    /// Inverse de `ParticipantRecord.player` — indispensable dès que CloudKit est actif : une
    /// relation sans inverse déclarée des deux côtés fait planter l'ouverture du container
    /// (contrainte CloudKit, doc 03 n°3), alors qu'elle passait silencieusement en local seul.
    /// Stockage optionnel : CloudKit exige que les relations vers plusieurs le soient (au-delà
    /// d'avoir une valeur par défaut) — masqué derrière `participations` ci-dessous.
    @Relationship(deleteRule: .nullify, inverse: \ParticipantRecord.player)
    public var participationsStorage: [ParticipantRecord]? = []

    public var participations: [ParticipantRecord] {
        get { participationsStorage ?? [] }
        set { participationsStorage = newValue }
    }

    public init(
        id: UUID = UUID(),
        nickname: String,
        avatarKind: String,
        avatarValue: String,
        avatarPhoto: Data? = nil,
        paletteID: String,
        createdAt: Date = Date(),
        isArchived: Bool = false,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.nickname = nickname
        self.avatarKind = avatarKind
        self.avatarValue = avatarValue
        self.avatarPhoto = avatarPhoto
        self.paletteID = paletteID
        self.createdAt = createdAt
        self.isArchived = isArchived
        self.sortIndex = sortIndex
    }
}
