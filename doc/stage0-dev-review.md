# Stage 0 dev review

Review of the Stage 0 commit (`6bc871c`), the fixes applied on top of it, and the items it hands
off to later stages. Design intent stays authoritative in `PLAN.md`; the task checklist lives in
`DEV_PLAN.md`. This file is the record of *why* these particular changes were made.

Reviewed: `LifeRPGCore` (models, CSV reader, seed parser, importer), the `LifeRPG` app target,
`LifeRPG.xcodeproj` settings, and the two seed CSVs.

---

## What was already right

- All 7 `@Model`s satisfy the CloudKit constraints: every property has a default or is optional,
  no `@Attribute(.unique)`, no relationships at all.
- Enums stored as raw Strings with computed accessors, as the SwiftData rules require.
- Core has no UI dependency and runs under plain `swift test`.
- Seeding is all-or-nothing per table: the whole CSV is parsed before anything is inserted, so a
  bad row can't leave the table half-populated.
- The CSV reader handles the cases the seed files actually contain: quoted commas, `""` escapes,
  newlines inside quotes, CRLF, missing trailing newline.

---

## Fixes applied

### 1. Versioned schema

`ModelContainer` was built from a bare `Schema(models)`. A `SchemaMigrationPlan` needs a
`VersionedSchema` as its starting point, and retrofitting one after real data exists is where
SwiftData stops recognising the old store.

`Models/Schema.swift` now declares `SchemaV1: VersionedSchema` (version `1.0.0`) plus an empty
`LifeRPGMigrationPlan`, and the container is opened with both.

**Rule going forward:** adding a property stays in V1 with no migration. Renaming, retyping or
removing one means a new `SchemaV2`, a `MigrationStage` appended to the plan, and a bump of the
exported JSON's `schemaVersion`.

### 2. Startup failure no longer crashes

`fatalError` on container creation meant a failed migration would kill the app at launch — with
the Stage 1 JSON export button unreachable inside that same app.

`LifeRPGApp` now keeps `container: ModelContainer?` and shows `StartupErrorView` when it's nil.
The catch branch deliberately does nothing else: **it never deletes or rebuilds the store**, so the
file survives and reinstalling the previous build gets the data back. The view shows the full
error, allows selecting it, and has a copy button.

### 3. CSV seeding is an additive merge

`seedIfEmpty` only ever ran against empty tables, so a quest added to a CSV after the first launch
could never reach the phone — awkward, because the plan is to expand the H pool after a couple of
weeks of use.

`SeedImporter.mergeSeeds` now runs on every launch and inserts only rows whose `text` isn't in the
DB yet. `Result` counts insertions, so a normal launch reports 0.

Consequences, all intended:

| Action | Effect |
|---|---|
| New row in the CSV | inserted on next launch |
| Edited text in the CSV | reads as a new row; the old one stays alongside it |
| Row deleted from the CSV | stays in the DB — the DB is the source of truth |
| Quest deactivated in the app | stays deactivated; text is known, so it's skipped |
| Quest hard-deleted in the app | comes back on next launch |

The last line is the reason the Stage 5 library UI must **soft-delete** (`isActive = false`) rather
than delete.

### 4. Tests

23 tests, up from 15. Hardcoded row counts (75 / 13 / 12) are gone — they'd break on every CSV
edit. Counts are now checked against what the parser returns, and the real invariants are asserted
directly:

- texts are unique in both CSVs (the merge keys on `text`, so a duplicate would be silently dropped)
- every EPIC has cooldown 0
- every `weekend_only` quest is H
- "Go to the office" is inactive
- an app-side edit survives a re-merge, and a CSV edit to a known text is ignored
- the container opens with `SchemaV1` + migration plan (catches a model missing from `SchemaV1.models`)

`swift test`: 23 passed. `xcodebuild -scheme LifeRPG`: BUILD SUCCEEDED.

---

## Enhancements implemented afterwards

The items below were written up as notes for later stages and then pulled forward, because each one
is either a silent failure mode or a data-loss path that gets harder to add once real history
exists. No `@Model` definition changed, so there is no migration impact. `swift test`: 59 passed.

### 5. Fixed calendars (`Core/Time/DayKey.swift`)

`Calendar.current` follows the user's region: it changes the first day of the week and even the
calendar system, which would move week boundaries and therefore Sunday settlement and the epic
week. `dayKey` now goes through a Gregorian calendar and `weekKey` through an ISO 8601 one, both
pinned to `en_US_POSIX` and taking the time zone as a parameter so tests can fix it.

`DayKey` also carries the string helpers the rest of the logic needs: `date` (anchored at noon, so
the round trip survives a DST change that happens at midnight — Havana, Santiago), `weekday`,
`isWeekend`, `adding`, `daysBetween`, and `range(after:through:)`, which is the catch-up loop's
day list (exclusive of the last processed day, inclusive of today).

Note `weekKey` uses the ISO **week-year**: 2027-01-01 is a Friday and reads `2026-W53`. Tested.

### 6. `frequency_spec` and `auto_verify` validated at import

Both were stored as-is, and both failed silently: an unparseable frequency meant the routine simply
never came due — no penalty, no error, no row on the today page — and a mistyped rule meant
auto-verification quietly never fired.

`FrequencySpec.parse(kind:spec:)` and `AutoVerifyRule.parse(_:)` now sit in `Core/Rules/`, and
`SeedParser` calls both, so `TUES`, `SATURDAY`, `1:SATURDAY`, `MON,MON`, `mindfull:15` and friends
throw `SeedError.invalidValue` with a line number. `SeedError.invalidValue` gained a `reason`
(defaulted to nil, so existing call sites are unchanged) and a `description`, which reads
`line 7, frequency_spec = 'TUES': 'TUES' is not a weekday code (SUN…SAT)` on the debug page.

Weekday codes are strictly three letters: `TUES` is a typo, not a synonym. `weekly_target` is also
checked against the spec — a target above the days the spec offers can never be met and would
report a shortfall every Sunday — but only as an upper bound, since "three slots offered, two
required" is a legitimate flexible routine.

The parsers are validation only: the models still store the raw strings, with `RoutineTask.frequency`
and `.autoVerify` as computed readings. Stage 2 still owns the scheduling question of *which*
`dayKey`s a parsed spec comes due on.

### 7. `StoreAudit` (`Core/Models/StoreAudit.swift`)

The enum getters fall back to `.easy` / `.low` / `.weekly` / `.normal` on an unknown raw value,
which keeps the app usable but hides a quest that would then score and cool down wrong forever.
`StoreAudit.issues(context)` scans every model for unknown enum raws, unparseable specs and rules,
and malformed `dayKey` / `weekKey` strings, returning one row per distinct value with a count. The
debug page shows it; Stage 6 should run it after a JSON import instead of trusting the fallback.

### 8. Rescue export in `StartupErrorView`

`fileExporter` now writes the store files straight off disk into a dated folder, bypassing
SwiftData entirely, so it works precisely when the container won't open. It exports `*.store`
together with its `-wal` and `-shm` sidecars — the WAL can hold writes that were never
checkpointed, so exporting the `.store` alone can lose recent days. The button is disabled, with a
note, when no store file is found.

Still true: the failure branch never deletes or rebuilds the store. Not yet exercised at runtime —
reaching this screen requires an actual broken container.

---

## Deliberately not fixed

- **UTF-8 BOM in a CSV.** The files are hand-edited, never exported from Excel or Numbers, and a
  BOM would fail loudly as `missingColumn("text")` on the debug page rather than corrupt anything.
- **Project-level `IPHONEOS_DEPLOYMENT_TARGET = 27.0`.** The target-level 17.6 overrides it, so
  there's no effect. It also lives in `project.pbxproj`, which is yours to edit in Xcode.

---

## Notes for later stages

### Stage 1 — Today page

- ~~Rescue path~~ and ~~fixed calendars~~ — done, see 5 and 8 above.
- **Injected `now` and RNG.** `ensureToday`, `sample` and `awardedPoints` take an injected date and
  `RandomNumberGenerator`, otherwise none of the sampling or rolling logic is testable.
- **Idempotency on `DailyContext`, not `DailyQuest`.** If every `sample()` returned nil there'd be
  no `DailyQuest` for the day and a second launch would regenerate the routine occurrences.
- **Catch-up loop.** The app may not be opened for days; every missed `dayKey` still needs its
  overdue penalties, day-4 auto-skips and Sunday settlement. `DayKey.range(after:through:)` is the
  day list; what to do per day is still Stage 1/2 work.

### Stage 2 — Routines

- ~~Validate `frequency_spec` and `auto_verify` at import~~ — done, see 6 above.
- What remains is scheduling: turning a parsed `FrequencySpec` into the `dayKey`s it comes due on.
  `everyNDays` counts from the last completion and `everyNWeeksOnWeekday` needs `anchorWeekKey`,
  neither of which the parser touches.

### Stage 5 — Library management

- Deleting a quest must be a soft delete (`isActive = false`), or the CSV merge re-inserts it.
- Once quests can be added in-app, the CSV merge can either stay as a bulk-import path or be
  narrowed back to first-launch seeding.

### Stage 6 — Import and migration

- **Unknown raw values.** The scanner exists (`StoreAudit`, see 7 above); what's left is calling it
  at the end of a JSON import — especially the web prototype's old save data — and refusing or
  reporting before the import is committed, rather than letting the fallback hide it.

---

## Still open (also tracked in `PLAN.md` §12)

- Flexible routines vs the escalating penalty: does the Sunday shortfall escalate into the
  following Monday and Tuesday, or is it a single deduction on Sunday?
- Weekend H exposure: Saturday leaves only 1 random slot and Sunday 2, so the 9 weekend-only H
  quests may rarely be drawn. Possibly guarantee an H slot on weekends.
- Whether the overdue penalty should still be scaled by readiness — it currently isn't, following
  the worked example (base 50 → −25 / −38 / −50).
