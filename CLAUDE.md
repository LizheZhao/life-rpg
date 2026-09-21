# Life RPG — iOS app

Personal-use life RPG app, single-user, not published to the App Store. Full design in `doc/PLAN.md`; quest library seed data in `doc/side_quests.csv` and `doc/routine_quests.csv`.

## Structure

- `LifeRPGCore/` — Swift Package holding models, rules, sampling and settlement logic. No UIKit/SwiftUI dependency, runnable directly with `swift test`
- `LifeRPG/` — Xcode app target: SwiftUI views, HealthKit / EventKit integration, import/export only
- `doc/` — PLAN.md, DEV_PLAN.md, and seed CSVs

Keep as much logic as possible in Core; views should only render. When working in Core you (Claude) only need the `swift` commands, not `xcodebuild`.

**Current status: Stage 2 in progress.** Stage 1 (day generation, catch-up, sampling, scoring, streak, ledger, today page, payout reveal, JSON/CSV exports, rating/comment log) is done. Stage 2 so far: frequency scheduling, routine occurrences, routine load → random slots, routine completion (incl. late half pay), the overdue ladder + day-4 auto-skip, flexible Sunday settlement, backlog section, flexible do-ahead, a two-week `ScenarioTests`, and simulator-only time travel on the debug page. Left: degraded_text, ad-hoc replacement. 227 Core tests. `doc/DEV_PLAN.md` is the task-level truth; read it before starting anything.

`tier` is still a stub: always `normal` until Stage 3 reads HealthKit (a `DayInputs` parameter, so wiring it is a one-line change at the call site). Routine load is **not** an input — `ensureToday` schedules the day's routines and counts them itself.

`LifeRPGCore` is a single library target + `LifeRPGCoreTests` (Swift Testing, Swift 5 language mode). `LifeRPG.xcodeproj` (target/scheme `LifeRPG`, iOS 17.6+, iPhone only) links the local package; `LifeRPG/` is a synchronized folder, so new files placed there are picked up without touching `project.pbxproj`. `@Model` requires full Xcode as the active developer dir (Command Line Tools lack the SwiftData macro plugin).

Seed CSVs: `doc/*.csv` is the single source of truth. `LifeRPG/Seed/*.csv` are symlinks to them (Xcode copies the real files into the bundle). Core's `SeedImporter.mergeSeeds` takes CSV strings and inserts only rows whose `text` the DB doesn't have yet; existing rows are never overwritten or deleted. The DB is the source of truth, the CSVs only add.

## Commands

- Build the logic layer: `swift build --package-path LifeRPGCore`
- Run tests: `swift test --package-path LifeRPGCore`
- Build the app (no simulator launch): `xcodebuild -scheme LifeRPG -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build`

## Rules

- **Never hand-edit `LifeRPG.xcodeproj/project.pbxproj`.** When a new file is needed, create it in the right directory and tell me to confirm it in Xcode — don't edit the project file yourself.
- Before changing an `@Model` definition, explain the impact on existing data. SwiftData's automatic migration only handles simple cases like adding fields; renaming or changing a type needs a migration plan.
- CloudKit-ready constraints: every `@Model` property must have a default value or be optional, no `@Attribute(.unique)`, all relationships optional. Breaking this will blow up later when CloudKit is turned on.
- Balance is always derived by summing `LedgerEntry`; never add a cached balance field.
- Quest text is snapshotted on the instance — never turn history records into references back to the template. `DailyQuest` **is** the per-day history the calendar and summary read: never overwrite a row to save adding one.
- `QuestRating` / `QuestComment` are append-only and dated. A changed opinion is a new row, never an overwrite — "what have I been rating highest lately" only works while the old rows survive.
- **A rule lives in exactly one place, in Core.** A view that needs one passes in the rows its `@Query` already holds (`Streak.completedDayKeys(_:)`, `Economy.balance(_:)`, `Economy.totalEarned(_:)`) rather than re-filtering or re-summing beside the HUD. This has already drifted twice; if a rule needs a `[Model]` overload to make that possible, add the overload.
- Anything derived from an already-awarded value takes that value as a parameter and never recomputes it — `Scoring.breakdown(_:tier:awarded:)` has no RNG in its signature on purpose, so the reveal animation physically cannot re-roll the points it is displaying.
- Dates always use `dayKey` (`"2026-09-17"`, local timezone) and `weekKey` (`"2026-W38"`) strings; never compare `Date` directly in business logic.
- Write tests in Core before new logic. Where `PLAN.md` states expected numbers (the reroll ladders, the penalty worked example), assert those literals rather than recomputing them with the formula under test.
- Never put credentials like the Oura token in code or tests — tokens go through Keychain.

## Communication

- Reply in Chinese; keep technical terms in English.
- Say plainly when something could not be verified, and correct it once it can be — a finding reported as certain and later disproved costs more than one reported as uncertain.
- Before touching more than two files, describe the plan first — don't just start writing.
- When design intent is unclear, check the relevant section of `doc/PLAN.md`; if PLAN doesn't cover it, ask me first.
