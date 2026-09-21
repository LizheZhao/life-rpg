import SwiftData

/// V1 of the store. Adding a property, or a whole new model, is a compatible change and
/// stays in V1 — SwiftData's lightweight migration handles both.
/// Renaming, retyping or removing one needs a new `SchemaV2` plus a `MigrationStage`
/// below, and a bump of the exported JSON's `schemaVersion`.
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] = [
        QuestTemplate.self,
        RoutineTask.self,
        DailyQuest.self,
        RoutineOccurrence.self,
        Reward.self,
        LedgerEntry.self,
        DailyContext.self,
        QuestRating.self,
        QuestComment.self,
    ]
}

public enum LifeRPGMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] = [SchemaV1.self]
    public static var stages: [MigrationStage] = []
}

public enum LifeRPGSchema {
    public static let current = Schema(versionedSchema: SchemaV1.self)

    /// For `#Preview` and tests that just need the model list.
    public static let models = SchemaV1.models
}
