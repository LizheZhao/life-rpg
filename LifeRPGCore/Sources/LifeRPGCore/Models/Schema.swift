import SwiftData

/// The store's schema.
///
/// A `VersionedSchema` can only ever describe the model classes **as they are now** — the classes
/// themselves are shared — so an older version listed beside it would describe the current shape
/// too, and SwiftData would find no path from what is actually on disk. There is therefore one
/// version here, bumped when the shape changes, and no migration stages: adding and removing a
/// property are both inferred by lightweight migration.
///
/// A change lightweight migration cannot infer — renaming, retyping, splitting a model — needs a
/// custom stage, and then the old shape has to be spelled out as its own set of model classes
/// first. Either way the exported JSON's `schemaVersion` gets bumped with it.
///
/// V2 dropped `intensity` from both libraries and `RoutineTask.degradedText`, and added
/// `downgradeIDs`, the occurrence's downgrade snapshot and `DailyContext.cycleDay`.
public enum SchemaV2: VersionedSchema {
    public static var versionIdentifier = Schema.Version(2, 0, 0)

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
    public static var schemas: [any VersionedSchema.Type] = [SchemaV2.self]
    public static var stages: [MigrationStage] = []
}

public enum LifeRPGSchema {
    public static let current = Schema(versionedSchema: SchemaV2.self)

    /// For `#Preview` and tests that just need the model list.
    public static let models = SchemaV2.models
}
