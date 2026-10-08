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
/// `downgradeIDs`, the occurrence's downgrade snapshot and `DailyContext.cycleDay`. V3 added
/// `Reward.isGoal`. V4 added `RoutineOccurrence.iconKey`, the doodle chosen for a custom ad-hoc
/// routine. Both are optional or defaulted, so lightweight migration fills them in. V4 is the first
/// to bump the export's `schemaVersion` (to 4); import still reads v3 files, whose occurrences
/// simply carry no `iconKey`. V5 added `originRaw` to both libraries (seed or the user's own),
/// defaulted to seed, so every existing row stays what it was; the export's `schemaVersion` goes to
/// 5 with the user's rows in a block of their own, and import still reads v3 and v4. V6 added
/// `JournalTurn`, a whole new model, which lightweight migration also infers; the export goes to
/// 6 with a `journal` block, and import still reads v3 to v5, whose files simply have no journal.
/// V7 added `JournalTurn.writingSeconds`, defaulted to 0, so existing turns read as no time
/// recorded; the export goes to 7 with the field on each turn, and import still reads v3 to v6,
/// where a turn without it decodes as 0. V8 added `JournalEntry`, one document per day, as a new
/// model that lightweight migration infers; no existing row is touched and `JournalTurn` stays. The
/// export goes to 8 with a `journalEntries` array, and import still reads v3 to v7, where entries
/// are built from the turns (`JournalMigration`). V9 added `isArchived` to both libraries,
/// defaulted to false, so every existing row stays listed; the export goes to 9 with the whole
/// library in a `fullLibrary` block (ids, edits, archived rows), and import still reads v3 to v8,
/// whose libraries it re-points by text as before. V10 added the optional `starterKey` to both
/// libraries (nil on every existing row, so nothing changes until `StarterUpdate.claim` stamps the
/// rows that match the starter library); the export goes to 10 with the key on each `fullLibrary`
/// row, and import still reads v3 to v9, whose rows simply have none.
public enum SchemaV10: VersionedSchema {
    public static var versionIdentifier = Schema.Version(10, 0, 0)

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
        JournalTurn.self,
        JournalEntry.self,
    ]
}

public enum LifeRPGMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] = [SchemaV10.self]
    public static var stages: [MigrationStage] = []
}

public enum LifeRPGSchema {
    public static let current = Schema(versionedSchema: SchemaV10.self)

    /// For `#Preview` and tests that just need the model list.
    public static let models = SchemaV10.models
}
