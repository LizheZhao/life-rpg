# Day rollover and time travel

Opening the app on a new day generates that day's epic, routines and slots, and judges the days it passed. Debug's time travel (simulator only) shifts the app's clock by whole days so this can be driven without waiting. Debug's `Testing` buttons put today back, either wholesale or just its results.

## Sub-features

- `roll-generate` a new day gets a `DailyContext` row and its quests.
- `roll-settle` days that ended are judged once: only routines are charged (fixed routines on the overdue ladder, flexible ones on Sunday); random slots left undone cost nothing. A routine that does not count toward clearing the day is never charged (its round still ends with a `skip` row), and each ended day is auto-verified from workout / mindful evidence before it is judged, so a logged workout can avoid a charge.
- `roll-idempotent` relaunching on the same day generates and charges nothing new (it still re-checks the epic and auto-verify on the existing day, and `Today's body data changed` can offer a re-plan if HealthKit returns a different tier; the simulator has no health data).
- `roll-05am` the day ends at 05:00, not midnight. Proved by a Core test only: time travel moves whole days, so it never crosses the boundary.
- `roll-reset` Debug → `Reset today` removes everything dated today with its payouts, ratings and notes and draws the day again; `Reopen quests` only undoes today's quest results (the same quests come back undone, nothing is redrawn). From source, not driven: an epic row dated today is not deleted by `Reset today` but reopened if it was paid today, the penalty and skip rows made by today's opening are kept, and make-up occurrences from earlier rounds are reopened rather than deleted.
- `roll-journal` rollover leaves journal entries alone; the journal's day is the same 05:00 day (`JournalSend.finishedDayKey`).

## How to get to it (user POV)

- Open the app after crossing 05:00 (cold launch or from the background).
- Simulator only: Settings tab → Developer → Debug → `Time travel (simulator only)` → `Advance one day`; `Back to the real date`. `Testing` (`Reset today`, `Reopen quests`) sits above it.

## Driving it with the simulator

Preconditions:

- `V up --fresh`, then complete one quest via [today-complete](./today-complete.md) so the first day has a result.
- Note `app day` from `V doctor` (call it D0).

- **Advance.** Run `V day 1`. The argument is an absolute offset (`V day 2` is one more day; `V day 1` twice is a no-op). It prints `offset=1; latest generated day <D0+1>`. Screenshot Today: the hand line reads D0+1 as `<Weekday> · <Mon> <d>` (e.g. `Sun · Oct 11`, plus `· N day streak` when there is one) and the slots are drawn for the new day.
- **Read what rolled.** Run `V sql "select ZDAYKEY, ZTIERRAW, ZRANDOMSLOTS, ZROUTINELOAD from ZDAILYCONTEXT order by ZDAYKEY"`: one row per generated day. Run `V ledger`: D0's entries are unchanged, and any new rows are routine charges: `penalty` rows dated each judged day (`<routine> — overdue day 1`, `… day 2`, `… day 3` for a fixed routine left open; `<routine> — 0/2 this week` for flexible ones when the judged day is a Sunday) and `skip` rows of 0 points. A `skip` row is written only when a fixed routine reaches round day 3 (dated due day + 3) or when Sunday's flexible settlement closes (dated the next day): advancing one day after an open fixed routine gives only the `overdue day 1` penalty. Driven (a Medium routine paying 21 left open from Thu 10-08): `V day 2` → `-11` dated 10-08; `V day 3` → also `-16` dated 10-09 (the occurrence's `ZPENALTYAPPLIED` reads the running total 27); `V day 4` → also `-21` dated 10-10, total 48, `ZSKIPPED=1` and a `skip` row dated 10-11; `V day 5` (the app day is a Monday) → Sunday's flexible settlement: `<routine> — 0/N this week` rows dated 10-11 and `skip` rows dated 10-12. A random slot left undone adds no row.
- **Idempotent.** Run `V relaunch` and repeat the queries; row counts and the balance are identical.
- **UI path.** Tap the Settings tab (x=340 pt, y=880 pt), scroll to the bottom, tap Debug (about 220, 723 pt there), scroll down to `Time travel (simulator only)` (about three screens: the page now holds Seed, Body, Journal model, Tables, Data audit, Testing, Time travel, Journal time, Ask me something, Old journal turns, Trends fixture, Journal hand-off, Quests by difficulty), and tap `Advance one day`. The `App day` row shows `<date>  (+N)` and `V doctor` agrees.
- **Return.** `V day 0` (or `Back to the real date`). Both work from either direction. Future rows stay by design.
- **Reset today (driven).** In Debug scroll to `Testing`, tap `Reset today` (about 114, 603 pt when `Testing` sits where the page leaves it after scrolling up from the Time travel section; read it from a screenshot), then `Reset` in the alert `Reset today?` (about 294, 559 pt). A note under the buttons reads `Reset: removed <n> quest(s) and <m> routine(s), reopened <k>, deleted <l> ledger entr(ies) and <r> rating/note(s); the day was generated again`. Before and after: `V sql "select Z_PK, ZDAYKEY, ZTIERRAW from ZDAILYCONTEXT where ZDAYKEY='<today>'"` shows a new `Z_PK` with the same tier; today's `quest` ledger row is gone (balance back to the grant), its `QuestRating` is gone, other days' rows are unchanged, and **a journal entry for today is still there** (`select count(*) from ZJOURNALENTRY where ZDAYKEY='<today>'`).
- **Reopen quests (from source, not driven).** The alert is `Reopen today's quests?` with `Reopen`; it deletes today's quest ledger rows, clears `completedAt` and points (and resets micro-action ticks), clears the templates' completion cooldown stamps, deletes the hidden quest row, and leaves occurrences, `DailyContext`, ratings and notes alone. An epic drawn today is in that set (it is reopened and counted); one drawn on an earlier day and done today is not touched. The note under the buttons reads `Reopened <n> quest(s), removed <m> hidden, deleted <l> ledger entr(ies)`.

## Gotchas

- Debug time travel is `#if targetEnvironment(simulator)`; there is no such control on a device. The `Testing` section (`Reset today`, `Reopen quests`) and the Settings → Developer → Debug row are not simulator-guarded, so they exist on a device build.
- Before 05:00 host time, "today" is yesterday's date: `V doctor` prints the app day (host clock, 05:00 rule and offset) and, separately, the latest generated day. D0 may equal yesterday's host date.
- Amounts are Core rules (`doc/PLAN.md`, `ScenarioTests`); don't assert them here, only that the screen matches `V ledger`. Observed on a Thursday-to-Sunday walk: a fixed routine left open drew `-13` (50% of its +25) on day 1; two flexible routines drew `-13` and `-15` on Sunday night. Observed on a Wednesday-to-Monday walk: the ladder 11 / 16 / 21 for a 21-point routine, and the level card's coins turned negative (`-99`) once the penalties outran the balance.
- `V day N` writes the app's container preferences and restarts the simulator's `cfprefsd`; setting the offset with `simctl spawn … defaults write` does not work once the app has written the key itself (after any tap on `Advance one day`).
- The Settings tab keeps whatever page was pushed (Debug, Library …) when you switch tabs and come back; a relaunch resets it to the Settings root. Check which page you are on before tapping a row.
- Time travel shifts the journal's day key (the Debug hand-off button and the day sheet follow it) but never its hour, so the `today` / `tonight` wording does not change with `V day N`; Debug → `Journal time` is what forces it.
- Going back does not undo anything. Start the next proof from `V up --fresh`, or use `Reset today` for today only.
