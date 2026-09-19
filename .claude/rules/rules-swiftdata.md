---
paths:
  - "LifeRPGCore/Sources/**/Models/*.swift"
  - "LifeRPGCore/Sources/**/*Model*.swift"
---

# SwiftData model rules

Before touching these files, confirm:

- Every property has a default value or is optional, no `@Attribute(.unique)`, all relationships optional (CloudKit-ready)
- Enums are stored as raw String fields (things like `difficultyRaw`), with a computed property converting back to the enum, since `#Predicate` is most reliable against raw values
- Date fields use `dayKey` / `weekKey` strings, never `Date` for business logic
- Quest text is snapshotted on `DailyQuest` and `RoutineOccurrence` (`textSnapshot`); soft-deleting a template must not affect history
- Never add a cached balance or cumulative-points field — both are derived from `LedgerEntry`

Adding a field is a compatible change, just add it. Renaming, changing a type, or removing a field requires a `SchemaMigrationPlan` first, plus bumping the exported JSON's `schemaVersion`, and updating the importer's handling of older versions.
