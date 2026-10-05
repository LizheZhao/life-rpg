# Day rollover and time travel

Opening the app on a new day generates that day's epic, routines and slots, and judges the days it passed. Debug's time travel (simulator only) shifts the app's clock by whole days so this can be driven without waiting. Debug's `Testing` buttons put today back, either wholesale or just its results.

## Sub-features

- `roll-generate` a new day gets a `DailyContext` row and its quests.
- `roll-settle` days that ended are judged once: only routines are charged (fixed routines on the overdue ladder, flexible ones on Sunday); random slots left undone cost nothing.
- `roll-idempotent` relaunching on the same day changes nothing.
- `roll-05am` the day ends at 05:00, not midnight. Proved by a Core test only: time travel moves whole days, so it never crosses the boundary.
- `roll-reset` Debug → `Reset today` removes everything dated today with its payouts, ratings and notes and draws the day again; `Reopen quests` only undoes today's quest results (the same quests come back undone, nothing is redrawn).
- `roll-journal` rollover leaves journal entries alone; the journal's day is the same 05:00 day (`JournalSend.finishedDayKey`).

## How to get to it (user POV)

- Open the app after crossing 05:00 (cold launch or from the background).
- Simulator only: Settings tab → Developer → Debug → `Time travel (simulator only)` → `Advance one day`; `Back to the real date`. `Testing` (`Reset today`, `Reopen quests`) sits above it.

## Driving it with the simulator

Preconditions:

- `V up --fresh`, then complete one quest via [today-complete](./today-complete.md) so the first day has a result.
- Note `app day` from `V doctor` (call it D0).

- **Advance.** Run `V day 1`. The argument is an absolute offset (`V day 2` is one more day; `V day 1` twice is a no-op). It prints `offset=1; latest generated day <D0+1>`. Screenshot Today: the date header reads D0+1 and the slots are drawn for the new day.
- **Read what rolled.** Run `V sql "select ZDAYKEY, ZTIERRAW, ZRANDOMSLOTS, ZROUTINELOAD from ZDAILYCONTEXT order by ZDAYKEY"`: one row per generated day. Run `V ledger`: D0's entries are unchanged, and any new rows are routine charges: `penalty` rows dated the ended day (`<routine> — overdue day 1` for a fixed routine left open; `<routine> — 0/2 this week` for flexible ones when the ended day is a Sunday) and `skip` rows of 0 points dated the next day. A random slot left undone adds no row.
- **Idempotent.** Run `V relaunch` and repeat the queries; row counts and the balance are identical.
- **UI path.** Tap the Settings tab (x=340 pt, y=880 pt), scroll to the bottom, tap Debug (about 220, 723 pt there), scroll down to `Time travel (simulator only)` (about three screens: the page now holds Seed, Body, Journal model, Tables, Data audit, Testing, Time travel, Journal card, Ask me something, Old journal turns, Trends fixture, Journal hand-off, Quests by difficulty), and tap `Advance one day`. The `App day` row shows `<date>  (+N)` and `V doctor` agrees.
- **Return.** `V day 0` (or `Back to the real date`). Both work from either direction. Future rows stay by design.
- **Reset today (driven).** In Debug scroll to `Testing`, tap `Reset today` (about 114, 603 pt when `Testing` sits where the page leaves it after scrolling up from the Time travel section; read it from a screenshot), then `Reset` in the alert `Reset today?` (about 294, 559 pt). A note under the buttons reads `Reset: removed <n> quest(s) and <m> routine(s), reopened <k>, deleted <l> ledger entr(ies) and <r> rating/note(s); the day was generated again`. Before and after: `V sql "select Z_PK, ZDAYKEY, ZTIERRAW from ZDAILYCONTEXT where ZDAYKEY='<today>'"` shows a new `Z_PK` with the same tier; today's `quest` ledger row is gone (balance back to the grant), its `QuestRating` is gone, other days' rows are unchanged, and **a journal entry for today is still there** (`select count(*) from ZJOURNALENTRY where ZDAYKEY='<today>'`).
- **Reopen quests (from source, not driven).** The alert is `Reopen today's quests?` with `Reopen`; it deletes today's quest ledger rows, clears `completedAt` and points, deletes the hidden quest row, and leaves occurrences, `DailyContext` and the epic alone.

## Gotchas

- Debug time travel is `#if targetEnvironment(simulator)`; there is no such control on a device.
- Before 05:00 host time, "today" is yesterday's date: `V doctor` prints the app day (host clock, 05:00 rule and offset) and, separately, the latest generated day. D0 may equal yesterday's host date.
- Amounts are Core rules (`doc/PLAN.md`, `ScenarioTests`); don't assert them here, only that the screen matches `V ledger`. Observed on a Thursday-to-Sunday walk: a fixed routine left open drew `-13` (50% of its +25) on day 1; two flexible routines drew `-13` and `-15` on Sunday night.
- `V day N` writes the app's container preferences and restarts the simulator's `cfprefsd`; setting the offset with `simctl spawn … defaults write` does not work once the app has written the key itself (after any tap on `Advance one day`).
- The Settings tab keeps whatever page was pushed (Debug, Library …) when you switch tabs and come back; a relaunch resets it to the Settings root. Check which page you are on before tapping a row.
- Time travel shifts the journal too: the Debug hand-off button and the day sheet follow the shifted clock, but an editor opened from a reader still says `tonight` by the real clock.
- Going back does not undo anything. Start the next proof from `V up --fresh`, or use `Reset today` for today only.
