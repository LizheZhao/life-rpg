# Life RPG — iOS app

Personal-use life RPG app, single-user, not published to the App Store. Full design in `doc/PLAN.md`; quest library seed data in `doc/side_quests.csv` and `doc/routine_quests.csv`.

## Structure

- `LifeRPGCore/` — Swift Package holding models, rules, sampling and settlement logic. No UIKit/SwiftUI dependency, runnable directly with `swift test`
- `LifeRPG/` — Xcode app target: SwiftUI views, HealthKit / EventKit integration, import/export only
- `doc/` — PLAN.md, DEV_PLAN.md, and seed CSVs

Keep as much logic as possible in Core; views should only render. When working in Core you (Claude) only need the `swift` commands, not `xcodebuild`.

**Current status: Stage 0 done.** `LifeRPGCore` is a single library target + `LifeRPGCoreTests` (Swift Testing, Swift 5 language mode). `LifeRPG.xcodeproj` (target/scheme `LifeRPG`, iOS 17.6+, iPhone only) links the local package; `LifeRPG/` is a synchronized folder, so new files placed there are picked up without touching `project.pbxproj`. `@Model` requires full Xcode as the active developer dir (Command Line Tools lack the SwiftData macro plugin).

Seed CSVs: `doc/*.csv` is the single source of truth. `LifeRPG/Seed/*.csv` are symlinks to them (Xcode copies the real files into the bundle). Core's `SeedImporter` takes CSV strings and seeds only into empty tables — after the first launch the DB is the user's copy.

## Commands

- Build the logic layer: `swift build --package-path LifeRPGCore`
- Run tests: `swift test --package-path LifeRPGCore`
- Build the app (no simulator launch): `xcodebuild -scheme LifeRPG -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build`

## Rules

- **Never hand-edit `LifeRPG.xcodeproj/project.pbxproj`.** When a new file is needed, create it in the right directory and tell me to confirm it in Xcode — don't edit the project file yourself.
- Before changing an `@Model` definition, explain the impact on existing data. SwiftData's automatic migration only handles simple cases like adding fields; renaming or changing a type needs a migration plan.
- CloudKit-ready constraints: every `@Model` property must have a default value or be optional, no `@Attribute(.unique)`, all relationships optional. Breaking this will blow up later when CloudKit is turned on.
- Balance is always derived by summing `LedgerEntry`; never add a cached balance field.
- Quest text is snapshotted on the instance — never turn history records into references back to the template.
- Dates always use `dayKey` (`"2026-09-17"`, local timezone) and `weekKey` (`"2026-W38"`) strings; never compare `Date` directly in business logic.
- Write tests in Core before new logic, especially these four areas: frequency parsing, overdue penalty, reroll pricing, and flexible routine weekly settlement.
- Never put credentials like the Oura token in code or tests — tokens go through Keychain.

## Communication

- Reply in Chinese; keep technical terms in English.
- Before touching more than two files, describe the plan first — don't just start writing.
- When design intent is unclear, check the relevant section of `doc/PLAN.md`; if PLAN doesn't cover it, ask me first.
