# Life RPG

A personal iOS app that turns daily life into a role-playing game, in the spirit of *Solo Leveling*. Each day it hands out a small set of quests, scores them with points, and lets you spend those points on real rewards. It is built for one person: no accounts, no social features, no App Store release.

## How it plays

- **Daily quests.** Each day draws a few random quests plus the routines due that day. The number of random quests shrinks on days with many routines, so a heavy day doesn't pile up.
- **Difficulty is resistance.** Tiers (T, E, M, H, EPIC) measure how much you don't want to do something, not how much effort it takes. "Message an old friend" can be harder than "walk by the river".
- **Energy-aware.** Sleep, HRV and resting heart rate from HealthKit give a daily energy score. Low-energy days get easier quests; high-energy days get harder ones.
- **Hidden quest and weekly epic.** Clearing everything unlocks a light bonus quest. One epic runs per week and can be extended, rerolled or replaced.
- **Routines with consequences.** An overdue routine loses points for up to three days and can be made up late for half credit. Routines have lighter versions for bad days.
- **Economy.** Points roll within each tier's range. You spend them on rewards you define, on virtual items, or on rerolls. The balance can go negative, and you level up as you earn.
- **Journal.** One document per day, with optional questions written by the on-device model (Foundation Models). A Shortcut can send the finished day to Apple Journal.
- **Recovery mode.** A run of easy days (for example after surgery): lighter routines, no new epic, no penalties.
- **History.** A monthly calendar, a day sheet for any past day, and a Trends tab once there is a week of journal entries.

The app has five tabs: **Today**, **Calendar**, **Trends**, **Rewards** and **Settings**.

## Project layout

| Path | What it holds |
|---|---|
| `LifeRPGCore/` | Swift package with the models, rules, sampling, scoring and settlement. No UIKit or SwiftUI, so it runs with `swift test`. |
| `LifeRPG/` | The SwiftUI app: views, HealthKit and EventKit integration, notifications, import and export. |
| `LifeRPG.xcodeproj` | Xcode project (scheme `LifeRPG`, iPhone only, iOS 17.6+). |
| `doc/` | Design docs: `PLAN.md` (the full game design), `DEV_PLAN.md` (stages and status), UI and journal specs, and `starter_library.json`. |

Most logic lives in Core; the views only render it.

## Tech stack

- SwiftUI, iOS 17.6+
- SwiftData for on-device storage
- HealthKit (sleep, HRV, resting heart rate, mindful minutes, cycle) and EventKit (workouts logged to the calendar)
- Foundation Models for journal questions, where the device supports it
- Manual JSON backup to iCloud Drive

## Building

You need full Xcode, not just the Command Line Tools, because SwiftData's `@Model` macro needs it.

Build the logic package:

```bash
swift build --package-path LifeRPGCore
```

Run the Core tests:

```bash
swift test --package-path LifeRPGCore
```

Build the app for the simulator:

```bash
xcodebuild -scheme LifeRPG -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

To run it on your own iPhone, open `LifeRPG.xcodeproj` in Xcode, choose your personal team under Signing, and run. With a free Apple ID the install expires after 7 days; running from Xcode again reinstalls it and keeps your data.

## Starter library

On first launch the app copies `doc/starter_library.json` (general quests and routines) into an empty store, once. After that, the library in the app is the source of truth: you edit, add and archive rows there. New rows added to the file later can be pulled in from a card at the top of the Library.

## Data

Everything stays on the device. Settings → Data exports a JSON backup (to iCloud Drive or anywhere else) and restores from one. The balance is always computed from the ledger, and history rows are never overwritten.

## Docs

- [`doc/PLAN.md`](doc/PLAN.md) — game design: tiers, daily structure, routines, energy, economy, data model
- [`doc/DEV_PLAN.md`](doc/DEV_PLAN.md) — development stages and current status
- [`doc/UI_DESIGN.md`](doc/UI_DESIGN.md) — visual design
- [`doc/JOURNAL_UX_SPEC.md`](doc/JOURNAL_UX_SPEC.md) — journal editor and calendar spec
- [`CLAUDE.md`](CLAUDE.md) — rules for working on the code
