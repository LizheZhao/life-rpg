# Calendar and day detail

The Calendar tab shows a month grid: each day's number sits in a progress ring (what was done over what the day asked), the ring turns violet once the hidden quest is done, and each epic is a hand-drawn marker stroke behind the dates from the day it was drawn to the day it was finished (or to its last day while unfinished), grey until done. Below it sit a legend and an `All journal entries` card; a round book button at the top right opens the same list. Tapping a day opens a bottom sheet with that day's net coins, routines, quests, the night's journal entry, spending and ratings.

## Sub-features

- `cal-grid` month grid; today's number is in the accent colour (inside its progress ring); days after today are dimmed and not tappable, and an empty day does not open. A cell whose ring is empty can still open when the day has rows (driven: a past day with only an open routine and its penalty rows opened). The padding days of the neighbouring months are tappable too, at 0.4 opacity.
- `cal-nav` previous / next month chevrons (next is disabled on the current month; a `This month` pill returns from another month).
- `cal-marks` (since commit 178e324) a progress ring per day: done over asked, counting the random quests (a trivial group as one) and the clear-gating routines done on time (`CalendarMarks.progress`); the ring is violet once the hidden quest is done. An epic is a marker stroke from its draw day to its done day, or, while unfinished, to the Sunday of its last week (+7 days per extension); grey until done, then one of four colours in turn (`CalendarMarks.epicSpans`). The legend has three chips: `Quests and routines done`, `Hidden too`, `Epic, grey until done`. The old tier dots, journal pencil, routines tick and star are gone; a journal entry shows only in the cell's accessibility value.
- `cal-detail` the day sheet (720 pt detent that can also be dragged to `.large`, drag indicator, **no `Done` button**: swipe down to close). Order: header (weekday, date, a `+N coins` pill that is the sum of that day's ledger rows, a tier pill reading `very low day` / `low day` / `normal day` / `high day`, absent when the day has no day setting; the coin text reads `+1 coin`, `0 coins`), `Routines` (collapsible, open by default, `<done> / <total> done`), `Quests` (collapsible, **closed** by default, `<done> / <total> done`; the total counts every row that is not replaced, the epic and the hidden quest included, so it is the random slots plus 1 on the day the epic was drawn: read it, don't assert a fixed number), `THAT NIGHT` (night card, whose right side reads `<time> · <n> words`, or `Nothing written` + `Write about this day`, shown only for today and earlier days), `Done this day for another day`, `Spending, penalties, skips`, `Other ratings this day`, `Body` (only when a day setting exists). Row marks: check for done, ring for open, dash for replaced / swapped / rerolled, cross for cancelled / skipped / missed.
- `cal-entries` the book button and the `All journal entries` card (`N entries, newest first`, or `Nothing written yet`) both open [the entries page](./journal-entries.md).
- `cal-missed` a routine nobody did reads `Did not finish` with a clay `-<penalty>` pill in the **Routines** section of its due day's sheet; the pill is the **running total** of its charges (11 + 16 + 21 = `-48` for a 21-point routine after all three rounds), while the coin pill of the due day holds only the round-1 charge (`-11 coins`) and rounds 2 and 3 sit under the later days' `Spending, penalties, skips`. Its `skip` ledger row (0 points) is dated due day + 3, not the next day, and appears on that later day's sheet. A routine that does not count toward clearing the day is never charged, so it shows no pill. The Calendar page itself has no `Did not finish` card any more (removed in commit c55f6ab).
- Ratings summary: the `Ratings` page no longer hangs off the Calendar; it is on [Trends](./trends.md).

## How to get to it (user POV)

- Tap the Calendar tab (x=160, y=880 pt); tap a day; tap the round `‹ ›` buttons to change month; tap the book button (about 402, 99 pt) or the `All journal entries` card.

## Driving it with the simulator

Preconditions:

- `V up --fresh`, then complete one quest and rate it +2 ([today-complete](./today-complete.md)).

- **Grid (driven 2026-10-12).** Tap Calendar. The grid shows the current month; the app's day (accent number) has a partly filled ring after one or two completions, and the week's epic is a grey stroke from the app day to that Sunday. The legend reads `Quests and routines done`, `Hidden too`, `Epic, grey until done`. A fresh store shows `All journal entries — Nothing written yet`. The Monday 12th sat at about 52, 353 pt (third row).
- **Detail.** Tap the app day's cell (locate it from the screenshot; Sunday the 4th sat at about 388, 255 pt). The sheet header shows the weekday in script over the date and the pills (`+125 coins` was 100 grant + 25 quest). The `Quests` header shows `1 / 3 done`; tap it to open the section, where the completed quest shows `+<points>` and `Rated +2`.
- **Cross-check.** `V sql "select ZDAYKEY, sum(ZPOINTS) from ZLEDGERENTRY group by ZDAYKEY"` for that day equals the coin pill (spending, penalties, skips and the grant included).
- **Night card.** With nothing written the card is an outlined `Nothing written` with `Write about this day →` (opens the editor for that day; `Done` there returns to the sheet). After writing, it becomes a dark card `THAT NIGHT <time> · <n> words` with a 3-line excerpt (text and answers, not the questions) and `Read the whole entry` (opens the reader, see [journal-entries](./journal-entries.md)).
- **Close.** Swipe the sheet down (from about y=300 to 900 pt); there is nothing to tap.
- **Missed routine (driven).** Needs a fixed-day routine open on a past day: on a Wednesday store `Take out the trash` is done, so first give another routine a due day (Library → `Change days`, see [library](./library.md); a Tue / Thu schedule makes it due on Thu D0+1). `V day 4` (the app day is D0+4) judges D0+3: open the Thursday cell (about 220, 319 pt in the second row; it carries no mark): header `-11 coins`, `normal day`, `Routines 0 / 2 done` with `Send job applications` `Did not finish` `-13` and `Take out the trash` `Did not finish` `-48` (cross icons), `THAT NIGHT` `Nothing written` + `Write about this day →`, and `Spending, penalties, skips` with `Penalty` `Take out the trash — overdue day 1` `-11`. `V ledger` shows the three `penalty` rows (10-08, 10-09, 10-10) and the `skip` row dated 10-11. For an occurrence due on D0 itself the same state is `V day 3`.

## Gotchas

- The coin pill for the first day includes the 100-coin starting grant, because the grant is dated that day (driven: `+119 coins` = 100 − 20 redeemed + 5 + 6 + 28; `V sql` agreed).
- The epic stroke starts on the day the epic was drawn and stops on the day it was finished; an unfinished one runs to its last day. `Seed 60 journal days` also writes done quests and routines, so it fills rings too.
- Rings show only for days with generated data; days after today are dimmed (not blank) and cannot be opened.
- A cell's accessibility value reads `N of M done`, then `hidden quest done`, `journal entry` and the epic when they apply; nothing here reads the accessibility tree, so prove a ring's fraction from the store (the day's done and asked rows), not from the drawing. `JournalMarks` (the three word-count bands) is still computed in Core but no longer drawn.
- A recovery day ([recovery](./recovery.md)) has no mark of its own on the grid; its sheet's tier pill reads `very low day`, and no new epic stroke starts inside a stretch.
- Section state (`Routines` open, `Quests` closed) is held for the session; re-opening a sheet keeps what you toggled.
- Time-travelled days appear as ordinary days.
- A month with rich history for screenshots: Debug → `Seed 60 journal days` (simulator only; see [trends](./trends.md)) writes entries and day settings, or restore a snapshot through Settings → Restore from JSON…. Both leave fixture data behind, so `V up --fresh` afterwards.
- At accessibility sizes the month grid is capped at `xxxLarge` by design; the legend, header and entries card scale fully.
