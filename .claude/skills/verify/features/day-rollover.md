# Day rollover and time travel

Opening the app on a new day generates that day's epic, routines and slots, and judges the days it passed. Debug's time travel (simulator only) shifts the app's clock by whole days so this can be driven without waiting.

## Sub-features

- `roll-generate` a new day gets a `DailyContext` row and its quests.
- `roll-settle` days that ended are judged once: only routines are charged (fixed routines on the overdue ladder, flexible ones on Sunday); random slots left undone cost nothing.
- `roll-idempotent` relaunching on the same day changes nothing.
- `roll-05am` the day ends at 05:00, not midnight. Proved by a Core test only: time travel moves whole days, so it never crosses the boundary.

## How to get to it (user POV)

- Open the app after crossing 05:00 (cold launch or from the background).
- Simulator only: Settings tab → Developer → Debug → `Time travel (simulator only)` → `Advance one day`; `Back to the real date`.

## Driving it with the simulator

Preconditions:

- `V up --fresh`, then complete one quest via [today-complete](./today-complete.md) so the first day has a result.
- Note `app day` from `V doctor` (call it D0).

- **Advance.** Run `V day 1`. The argument is an absolute offset (`V day 2` is one more day; `V day 1` twice is a no-op). It prints `offset=1; latest generated day <D0+1>`. Screenshot Today: the date header reads D0+1 and the slots are drawn for the new day.
- **Read what rolled.** Run `V sql "select ZDAYKEY, ZTIERRAW, ZRANDOMSLOTS, ZROUTINELOAD from ZDAILYCONTEXT order by ZDAYKEY"`: one row per generated day. Run `V ledger`: D0's entries are unchanged, and any new rows are routine charges: `penalty` rows dated the ended day (`<routine> — overdue day 1` for a fixed routine left open; `<routine> — 0/2 this week` for flexible ones when the ended day is a Sunday) and `skip` rows of 0 points dated the next day. A random slot left undone adds no row.
- **Idempotent.** Run `V relaunch` and repeat the queries; row counts and the balance are identical.
- **UI path.** Tap the Settings tab (x=309 pt, y=880 pt), scroll to the bottom, tap Debug (about y=722 pt there), scroll down about two screens to `Time travel (simulator only)`, and tap `Advance one day`. The `App day` row shows `<date>  (+N)` and `V doctor` agrees. Confirm the same way.
- **Return.** `V day 0` (or `Back to the real date`). Both work from either direction. Future rows stay by design.

## Gotchas

- Debug time travel is `#if targetEnvironment(simulator)`; there is no such control on a device.
- Before 05:00 host time, "today" is yesterday's date: `V doctor` prints the app day (host clock, 05:00 rule and offset) and, separately, the latest generated day. D0 may equal yesterday's host date.
- Observed on a Thursday-to-Sunday walk: a fixed routine left open drew `-13` (50% of its +25) on day 1; two flexible routines drew `-13` and `-15` on Sunday night. Amounts are Core rules (`doc/PLAN.md`, `ScenarioTests`); don't assert them here, only that the screen matches `V ledger`.
- `V day N` writes the app's container preferences and restarts the simulator's `cfprefsd`; setting the offset with `simctl spawn … defaults write` does not work once the app has written the key itself (after any tap on `Advance one day`).
- Going back does not undo anything. Start the next proof from `V up --fresh`.
