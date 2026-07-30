import Domain
import Foundation
import SwiftData

/// Doc 03 « MatchRecord » — une partie, du premier tap à l'archivage. `eventLogData` est **la
/// source de vérité** (doc 04 « Event sourcing ») ; la reprise après relance rejoue ce journal,
/// elle ne lit jamais un total mis en cache.
@Model
public final class MatchRecord {
    public var id: UUID = UUID()
    public var gameID: String = ""
    public var rulesVersion: Int = 1
    public var variantsData: Data = Data()
    public var startedAt: Date = Date()
    public var endedAt: Date?
    public var statusRaw: String = MatchStatus.inProgress.rawValue
    public var endReasonRaw: String?
    /// Masque la partie de l'onglet Historique sans y toucher — les statistiques de profil
    /// continuent de l'inclure, au même titre que l'archivage d'un `PlayerRecord`.
    public var isArchived: Bool = false
    /// Identifiant d'appareil créateur — utile en sync (Phase 8), placeholder en attendant.
    public var deviceOrigin: String = "local"
    public var eventLogData: Data = Data()

    // CloudKit exige que les relations vers plusieurs soient elles-mêmes optionnelles (au-delà
    // d'avoir une valeur par défaut) — d'où ce stockage optionnel, masqué derrière `participants`
    // ci-dessous pour que le reste du code continue de lire/écrire un tableau ordinaire (même
    // pont que `statusRaw`/`status` juste en dessous).
    @Relationship(deleteRule: .cascade, inverse: \ParticipantRecord.match)
    public var participantsStorage: [ParticipantRecord]? = []

    public var participants: [ParticipantRecord] {
        get { participantsStorage ?? [] }
        set { participantsStorage = newValue }
    }

    public init(
        id: UUID = UUID(),
        gameID: String,
        rulesVersion: Int,
        variantsData: Data,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        status: MatchStatus = .inProgress,
        endReasonRaw: String? = nil,
        deviceOrigin: String = "local",
        eventLogData: Data,
        participants: [ParticipantRecord] = []
    ) {
        self.id = id
        self.gameID = gameID
        self.rulesVersion = rulesVersion
        self.variantsData = variantsData
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.statusRaw = status.rawValue
        self.endReasonRaw = endReasonRaw
        self.deviceOrigin = deviceOrigin
        self.eventLogData = eventLogData
        self.participants = participants
    }

    public var status: MatchStatus {
        MatchStatus(rawValue: statusRaw) ?? .inProgress
    }
}
