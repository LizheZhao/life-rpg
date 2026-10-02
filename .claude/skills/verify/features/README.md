# LifeRPG verification map

This directory is the maintained source for verifying the user-facing behavior of the LifeRPG iOS app. Read the index before driving the app, then use the matching feature file as the recipe. `V` below means `.claude/skills/verify/scripts/verify.sh`.

## Baseline preconditions

- Run `V up --fresh` for a clean store: 76 quest templates, 20 routines, one `grant` ledger row of 100 ("Starting balance"), today generated.
- Run `V doctor` and require: `build: up to date`, `running: yes`, `offset: 0 day(s)`, and note `app day` (the date every recipe means by "today").
- Pass `V udid` as `device` to every simulator `control` call. Never drive any other simulator.
- Time-travel recipes leave future-dated rows; start the next recipe from `V up --fresh`.

## Driving conventions

- Drive by visible label and screenshot. Screenshot before and after every tap; convert shown px to points with ÷ 2.093 (921-px-wide image) or ÷ 3 (full 1320×2868).
- The floating tab bar is at y = 880 pt; x = 130 / 189 / 250 / 309 for Today / Calendar / Rewards / Settings. Library, the design gallery and Debug are pages inside Settings.
- Wait for sheet and alert dismissal before the next tap (a tap during the animation is swallowed).
- Never write to the store; read it with `V sql` / `V ledger`.

## Proof and skip reporting

- Capture the user action and the resulting state, not only the final screen.
- UI proof: a screenshot via `V shot <feature-id>-<step>` showing the screen and the level card's coin count.
- Mutation proof: a read-only second view from the store (`V ledger`, `V sql`) whose numbers equal the screen's.
- Record the feature ID and entry point used with every artifact; evidence lives in `build/verify-evidence/`.
- Report an unreachable path with the attempted step and the unmet precondition. Do not report a skipped entry point as verified through a different path.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior. It then uses exactly four H2 sections in this order: `Sub-features`, `How to get to it (user POV)`, `Driving it with the simulator`, `Gotchas`.

## Features

- [Today: complete a quest](./today-complete.md) — the complete button → confirm → payout reveal → rating path, plus the `⋯` menus. **Driven end to end.**
- [Day rollover and time travel](./day-rollover.md) — opening the app on a new day generates and settles. **Driven (generation); settlement penalties not yet observed.**
- [Calendar and day detail](./calendar.md) — month grid, marks, per-day sheet. **Driven.**
- [Rewards](./rewards.md) — balance, add/edit/redeem/goal, streak freeze. **Balance driven; add/redeem not yet driven.**
- [Library](./library.md) — template list, ratings, notes. **Not yet driven.**
- [Export and restore JSON](./export-restore.md) — Settings → Data, the system file panels. **JSON export and restore driven end to end; CSV export panel seen.**
