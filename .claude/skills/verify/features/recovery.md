# Recovery

Settings → Recovery sets a stretch of easy days (after surgery, say), from the day it is turned on through a last day, two weeks by default. Every day inside it is planned as a `Running low` whatever the body data says: the random slots are trivial, easy, easy, a routine harder than easy switches to its easy light version or rests until the stretch is over, no new epic is drawn (one already running stays), and nothing is charged for what stays undone. Each day keeps its mark (`DailyContext.isRecovery`), so it stays penalty-free after the stretch ends. Today shows a pill `Recovery · through <Mon d>` under the greeting.

## Sub-features

- `rec-switch` Settings → section `Recovery` → switch `Recovery`, with the footer `Each day draws only trivial and easy quests. Routines harder than easy switch to an easy light version, or wait until you're back. No new epic, and nothing is charged for what stays undone.` On sets the stretch from today through today + 13; off clears it (days already planned keep their mark).
- `rec-last` a `Last day` date picker under the switch while it is on; it never goes earlier than today.
- `rec-replan` turning it on or off with today already drawn raises a card titled `Recovery`: `Recovery starts today: only trivial and easy quests, and nothing is charged.` (or `Recovery is over: today goes back to what your readings say.`) followed by the same counts as the body-data re-plan (`N quest(s) stay as they are — …`, `N open slot(s) the new day no longer has would be dropped.`, `N new slot(s) would be drawn.`, `N open routine(s) would swap to (or back from) a lighter version.`), with `Re-plan what's open` and `Leave it`. Finished work is never touched; a dropped slot is a `DailyQuest` row with `ZREPLACED=1`, `ZREPLACEDREASONRAW='replan'`.
- `rec-plan` a recovery day: level card `Running low`, `3 quests today` (T, E, E), routines above easy as `light version` rows (`Light version · <original>` with `Do original`), an epic drawn before the stretch kept (its range rises with the very-low pay), no new epic from the next week on.
- `rec-pill` Today's `Recovery · through <Mon d>` pill, read from the day's mark.
- `rec-nocharge` no overdue ladder and no Sunday shortfall inside the stretch: a round still ends, with a `skip` ledger row of **0** points, and a flexible routine's Sunday shortfall is a 0-point `skip` too. The `-N Sun night` pill disappears from routine rows.
- `rec-export` the mark travels in the JSON backup (`dailyContexts[].isRecovery`, schema 12) and is restored ([export-restore](./export-restore.md)).

## How to get to it (user POV)

- Settings tab → second section `Recovery` (right under `You`) → the switch, then `Last day`. Accept `Re-plan what's open` on the card that follows. Turn the switch off to end the stretch early.

## Driving it with the simulator

The switch and the date picker are SwiftUI controls the control tool can't change, so set the stretch through the app's preferences with `V pref` (`recovery.firstDayKey` and `recovery.lastDayKey`, `yyyy-MM-dd` strings; empty or absent = off). Take the days from `V doctor`'s `app day`.

- **Start it (driven 2026-10-12).** `V up --fresh`, complete a quest or two so there is finished work to keep, then `V pref recovery.firstDayKey string <app day>` and `V pref recovery.lastDayKey string <app day + 13>` (each relaunches). The `Recovery` card is up on Today; tap `Re-plan what's open` (about 220, 590 pt with four count lines; read it from `V shot`). Today then shows the pill, `Running low`, the routine as `light version` and the open hard slot gone. `V sql "select ZDAYKEY, ZTIERRAW, ZISRECOVERY, ZRANDOMSLOTS from ZDAILYCONTEXT"` → `<day> | veryLow | 1 | 3`; `V sql "select ZSLOTRAW, ZREPLACED, ZREPLACEDREASONRAW, ZCOMPLETEDAT is not null, ZTEXTSNAPSHOT from ZDAILYQUEST order by Z_PK"` shows the finished quests untouched, the dropped one `1 | replan`, and new `easy` / `trivial` rows; `V sql "select ZTEXTSNAPSHOT, ZUSEDDEGRADED from ZROUTINEOCCURRENCE"` → the routine with `1`.
- **No charge (driven).** From there `V day 4`, then `V day 7` (past Sunday): every `ZDAILYCONTEXT` row has `ZISRECOVERY=1`, and `V ledger` shows only `skip | 0` rows (the fixed routine's round and the flexible routine's Sunday shortfall) — compare an ordinary run, where the same days write `overdue day N` penalties and a negative Sunday row.
- **Stop it.** `V pref recovery.lastDayKey --delete` (either key empty means off; delete both to match what the switch writes); with today drawn the `Recovery is over…` card appears. Not driven this pass.
- **The Settings switch.** It reads the same keys, so after `V pref` it shows on, with `Last day`. Flipping it by tap is unreachable.
- Start every other recipe from `V up --fresh`: the uninstall removes the container plist, so the stretch does not carry over (checked with `V pref recovery.lastDayKey` → `(not set)`).

## Gotchas

- The pill and the level card read the day's mark, not the preference: a day drawn before the stretch was set shows neither until the card's `Re-plan what's open` (`Leave it` keeps the day as it was; whether the card then comes back on the next foreground was not driven).
- Debug → `Reset today` on a recovery day draws the day again as a recovery day: `DayReset.reset` keeps the day's mark as it keeps its tier (`WholeDayResetTests.aRecoveryDayIsDrawnAgainAsARecoveryDay`). Driven 2026-10-12 after the fix: `ZISRECOVERY` stays 1, the slots are `easy, easy, trivial`, the pill and `Running low` stay, and a relaunch raises no `Recovery` card. (Before the fix the mark was lost until the next foreground's re-plan.)
- On a fresh install whose name was never asked, the name sheet and the `Recovery` card are both due at launch and neither showed (2026-10-12); `V pref profile.asked bool true` first, or answer the sheet, then set the stretch.
- Rested routines (harder than easy with no easy light version) get no occurrence at all on a recovery day, so there is nothing to see or rate for them.
- The rules (tier, slots, which routines rest, the waived charges) are covered by `RecoveryTests` and the Overdue / Replan tests in Core; this recipe proves the switch's state reaches the day and the screen.
