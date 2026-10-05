# LifeRPG verification map

This directory is the maintained source for verifying the user-facing behavior of the LifeRPG iOS app. Read the index before driving the app, then use the matching feature file as the recipe. `V` below means `.claude/skills/verify/scripts/verify.sh`.

## Baseline preconditions

- Run `V up --fresh` for a clean store: 76 quest templates, 20 routines, one `grant` ledger row of 100 ("Starting balance"), today generated.
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

Status is as of the last maintenance pass (2026-10-05, app at commit `87c9f61`). The pass was interrupted once: a second session in the `cleanup-today` worktree reset the shared `LifeRPG-Verify` simulator mid-run, which is why the harness now gives each checkout its own simulator; the steps that the reset interrupted were re-driven afterwards.

- [Today: complete a quest](./today-complete.md) — the complete button → confirm → payout reveal → rating path, the `⋯` menus, `+` add from library, the journal entry points. **Driven** (complete, rate, routine and reroll in the earlier pass; complete, rate and the `+` library path in this one). Not driven: Cancel / Replace / Extend, the `+` Custom tab, Ahead `Do now`, the Levels sheet contents.
- [Day rollover and time travel](./day-rollover.md) — generation, settlement, `Reset today`. **Driven**, including the Debug button and `Reset today`. `Reopen quests` and `roll-05am` are not (a Core test covers the boundary).
- [Calendar and day detail](./calendar.md) — month grid, marks, the redesigned day sheet, entries card. **Driven** (grid, legend, sheet, night card, close by swipe). Not driven: a missed routine on a past day's sheet.
- [Rewards](./rewards.md) — balance, add, goal, redeem. **Driven**: add, `Set as goal`, the goal row on Today's level card, redeem. Not driven: Edit, Archive, streak freeze; the editor's `Saving for this` switch is unreachable by tap.
- [Library](./library.md) — tiers, search, detail, re-rating, notes, and the new Settings card. **Driven**: quests (before the Settings card existed), the Routines list, a routine detail and the `Pays` stepper. Not driven: the `On` switch (unreachable by tap), the quest-detail steps since the Settings card was added.
- [Export and restore](./export-restore.md) — Settings → Data, the system file panels, the journal in the backup. **Driven end to end including export → reinstall → restore** (52 journal entries, 60 ratings, balance and a done entry all came back); CSV panel opened and dismissed. Not driven: the `Import failed` banners.
- [Workout detection](./workout-detection.md) — Settings → Workout detection. **Page and the access/calendar states driven** (`simctl privacy grant calendar`). A detected workout is unreached: creating the event is unproven.
- [Journal editor](./journal-editor.md) — typing, chips, `Ask me something` (real model and the safety card), `Done`. **Driven.** Not driven: the forced Debug results, Return/Backspace block behaviours, the Apple Journal hand-off.
- [Journal entries and reader](./journal-entries.md) — the entries page, search, the reader, the calendar's night card. **Driven** (page, search empty state, reader from a day sheet). Not driven: the sent / edited line, row → reader, previous/next pills.
- [Trends](./trends.md) — locked state, unlock by seeding, every card. **Driven.** Not driven: the Ratings page itself, a `Low energy days` card (needs low-tier days), Weeks and Year periods.
