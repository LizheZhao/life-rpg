# Day rollover and time travel

Opening the app on a new day generates that day's epic, routines and slots, and judges the days it passed. Debug's time travel (simulator only) shifts the app's clock by whole days so this can be driven without waiting.

## Sub-features

- `roll-generate` a new day gets a `DailyContext` row and its quests.
- `roll-settle` days that ended are judged (penalties, streak), once.
- `roll-idempotent` relaunching on the same day changes nothing.
- `roll-05am` the day ends at 05:00, not midnight.

## How to get to it (user POV)

- Open the app after crossing 05:00 (cold launch or from the background).
- Simulator only: Settings tab → Debug → `Advance one day`; `Back to the real date`.

## Driving it with the simulator

Preconditions:

- `V up --fresh`, then complete one quest via [today-complete](./today-complete.md) so the first day has a result.
- Note `app day` from `V doctor` (call it D0).

- **Advance.** Run `V day 1`. It prints `app day now <D0+1>`. Screenshot Today: the date header reads D0+1 and the slots are drawn for the new day.
- **Read what rolled.** Run `V sql "select ZDAYKEY, ZTIERRAW, ZRANDOMSLOTS, ZROUTINELOAD from ZDAILYCONTEXT order by ZDAYKEY"`: one row per generated day. Run `V ledger`: D0's entries are unchanged.
- **Idempotent.** Run `V relaunch` and repeat the two queries; row counts and the balance are identical.
- **UI path.** Tap the Settings tab (x=309 pt, y=880 pt), then Debug (y=674 pt), find `Advance one day`, tap it; the `App day` row shows `<date>  (+N)`. Confirm the same way.
- **Return.** `V day 0` (or `Back to the real date`). Future rows stay by design.

## Gotchas

- Debug time travel is `#if targetEnvironment(simulator)`; there is no such control on a device.
- Before 05:00 host time, "today" is yesterday's date: `V doctor` shows both. D0 may equal yesterday's host date.
- In the authoring run, advancing one day with two slots left undone on D0 added no ledger row. Whether that is correct is a Core rule (`doc/PLAN.md`, `ScenarioTests`), unconfirmed here. Don't assert penalty amounts in this recipe; use it to show the app triggers the pass and the screen matches `V ledger`.
- Going back does not undo anything. Start the next proof from `V up --fresh`.
