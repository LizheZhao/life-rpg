# LifeRPG verification map

This directory is the maintained source for verifying the user-facing behavior of the LifeRPG iOS app. Read the index before driving the app, then use the matching feature file as the recipe. `V` below means `.claude/skills/verify/scripts/verify.sh`.

## Baseline preconditions

- Run `V up --fresh` for a clean store: 108 quest templates and 19 routines (the starter library, `doc/starter_library.json`; before 2026-10-07 the author's CSVs seeded 76 and 20), one `grant` ledger row of 100 ("Starting balance"), today generated.
- Run `V doctor` and require: `build: up to date`, `running: yes`, `offset: 0 day(s)`, and note `app day` (the date every recipe means by "today").
- Pass `V udid` as `device` to every simulator `control` call. Never drive any other simulator. This checkout owns exactly one (`LifeRPG-Verify-<hash>`); a second session in another worktree gets its own, and a session that finds a store it did not write has met a second driver on the same simulator.
- Time-travel recipes leave future-dated rows; start the next recipe from `V up --fresh`.
- The random-slot count depends on the day (3 on a quiet weekday, fewer on a weekend with 4–6 routines), so don't assume `3 random slots`; read it off the level card.

## Driving conventions

- Drive by visible label and screenshot. Screenshot before and after every tap; convert shown px to points with ÷ 2.093 (921-px-wide image) or ÷ 3 (full 1320×2868).
- The floating tab bar is at y = 880 pt; x = 100 / 160 / 220 / 280 / 340 for Today / Calendar / Trends / Rewards / Settings. Library, Workout detection, the design gallery and Debug are pages inside Settings, which remembers the pushed page across tab switches.
- Wait for sheet, card and alert dismissal (and for a card to finish opening) before the next tap; a tap during the animation is swallowed.
- Scroll with a swipe that starts around y=760 pt and ends at 200–300 pt, away from the floating bar.
- Never write to the store; read it with `V sql` / `V ledger`.
- The control tool's screenshot lags the screen by several seconds and its taps do not flip SwiftUI switches. Read state with `V shot` (or a store query), and when a switch matters, reach the same state another way or report it unreachable.

## Proof and skip reporting

- Capture the user action and the resulting state, not only the final screen.
- UI proof: a screenshot via `V shot <feature-id>-<step>` showing the screen and the level card's coin count.
- Mutation proof: a read-only second view from the store (`V ledger`, `V sql`) whose numbers equal the screen's.
- Record the feature ID and entry point used with every artifact; evidence lives in `build/verify-evidence/`.
- Report an unreachable path with the attempted step and the unmet precondition. Do not report a skipped entry point as verified through a different path.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior. It then uses exactly four H2 sections in this order: `Sub-features`, `How to get to it (user POV)`, `Driving it with the simulator`, `Gotchas`.

## Features

Status is as of the last maintenance pass (2026-10-07, app = commit `cea398b` plus the uncommitted Library work: schema 9, rename / delete / archive, the pencil `Edit` sheet, backup v9, and the journal-ask edits then in the working tree). Every feature file was re-read against the source by one reader each and every feature was driven once on the current build; the corrections are in the files.

- [Today: complete a quest](./today-complete.md) — the complete button → confirm → payout reveal → rating path, the `⋯` menus, `+` add from library, the journal entry points. **Driven**: routine complete, quest complete and rate, the `⋯` popover, reroll with its ledger and row effects, the Levels sheet, the Ahead stack fan-out, the `Add for today` sheet. Not driven: Cancel / Replace / Extend purchases, the `+` Custom tab, Ahead `Do now`, the system context menu on long-press, micro-action tiles.
- [Day rollover and time travel](./day-rollover.md) — generation, settlement, `Reset today`. **Driven**: `V day 1…5` with the full overdue ladder (11 / 16 / 21), the skip row at due + 3, Sunday's flexible settlement and a negative balance. Not driven this pass: `Reset today` and `Reopen quests` (driven in earlier passes / from source), `roll-05am` (a Core test covers the boundary).
- [Calendar and day detail](./calendar.md) — month grid, marks, the redesigned day sheet, entries card. **Driven**, including a missed routine on a past day's sheet (`Did not finish`, cumulative `-48`, the penalty row) and the night card. Not driven: Weeks of other months, the pencil shades.
- [Rewards](./rewards.md) — balance, add, goal, redeem. **Driven**: add (cost 2 → `20 coins`), `Set as goal` (the `Saving for` card), redeem and its ledger row. Not driven: Edit, Archive, streak freeze, the goal row on Today's level card; the editor's `Saving for this` switch is unreachable by tap.
- [Library](./library.md) — tiers, search, detail, difficulty, `Change days`, add (epic, trivial), rename, delete with its confirmation, the `Archived` section and `Restore`. **Driven**, V8 → V9 store upgrade included (done on the previous build's store). Not driven: the `On` switch (unreachable by tap), a routine delete, a routine add, the taken-name refusal.
- [Export and restore](./export-restore.md) — Settings → Data, the system file panels, the whole library and the history in the backup (schema 9). **Driven end to end** twice (export → `V up --fresh` → restore with a byte-identical library and equal counts, a negative balance, `Not yet`). Not driven: the `Import failed` banners, the CSV panel (driven earlier).
- [Workout detection](./workout-detection.md) — Settings → Workout detection. **Driven**: the page unauthorised and authorised (`simctl privacy grant calendar`), selecting a calendar, a keyword, the check and its reason line. A detected workout is `verified-unreachable`: `simctl` cannot create a calendar event and the `.ics` route fails.
- [Journal editor](./journal-editor.md) — typing, chips, `Ask me something` (the safety card; the real model was not asked this pass), `Done`. **Driven.** Not driven: the forced `Ask me something` Debug results, Return / Backspace block behaviours, the Apple Journal hand-off, the `Journal time` forcing.
- [Journal entries and reader](./journal-entries.md) — the entries page, search, the reader, the calendar's night card. **Driven** (page, search and its clear / close behaviour, the reader from a row, the night card). Not driven: the sent / edited line, previous / next pills.
- [Trends](./trends.md) — locked state, unlock by seeding, every card. **Driven**, including the `Low energy days` card (the fixture produced one `low` day). Not driven: the Ratings page itself, Weeks and Year periods.
- [Name and starting over](./profile.md) — the first-launch name page, Settings → You, the greeting, Settings → Data → `Erase all records…`. **Driven** (first launch, the name in the greeting and Settings, the card's counts, `Not yet`, `Erase everything` and what is left). Not driven: editing the name from Settings, `Skip`.
- [Reminders](./reminders.md) — Settings → Reminders, Debug → Reminders. **Driven**: the permission prompt and `Allow`, both switches on (through the app's defaults, since a `Toggle` can't be tapped), the 14-day queue with its past-time rule, and cancelling tonight's by writing and leaving. Not driven: an actual delivery, the denied path, the switches by tap.
