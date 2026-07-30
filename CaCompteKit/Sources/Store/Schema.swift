import Foundation
import SwiftData

/// Doc 03 « Migrations » — `VersionedSchema` posé dès la v1, même vide de plan : le créer après
/// coup coûte plus cher qu'une base vide au départ.
public enum CaCompteSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    public static var models: [any PersistentModel.Type] { [PlayerRecord.self, MatchRecord.self, ParticipantRecord.self] }
}

public enum CaCompteMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [CaCompteSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
