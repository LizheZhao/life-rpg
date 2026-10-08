# Calendar and day detail

The Calendar tab shows a month grid: up to three dots per day coloured by the tier of each random quest done, then on one row a journal pencil, a routines tick and a violet hidden-quest star, and a soft band behind an epic week. Below it sit a legend and an `All journal entries` card; a round book button at the top right opens the same list. Tapping a day opens a bottom sheet with that day's net coins, routines, quests, the night's journal entry, spending and ratings.

## Sub-features

- `cal-grid` month grid with today ringed and marks for days with data; days after today are dimmed and not tappable, and an empty day does not open. A cell with no mark can still open when the day has rows (driven: a past day with only an open routine and its penalty rows had no dot, tick or pencil but opened). The padding days of the neighbouring months are tappable too, at 0.4 opacity.
- `cal-nav` previous / next month chevrons (next is disabled on the current month; a `This month` pill returns from another month).
- `cal-marks` dots (completed, non-replaced, non-epic, non-hidden random quests; the easiest kept, a trivial group counts once), pencil (a journal entry that day, three shades by word count: under 100, 100–299, 300+; the legend chip reads `Journal, darker is longer`), tick (every clear-gating routine due that day done on its due day or ahead), star (hidden quest done).
- `cal-detail` the day sheet (720 pt detent that can also be dragged to `.large`, drag indicator, **no `Done` button**: swipe down to close). Order: header (weekday, date, a `+N coins` pill that is the sum of that day's ledger rows, a tier pill reading `very low day` / `low day` / `normal day` / `high day`, absent when the day has no day setting; the coin text reads `+1 coin`, `0 coins`), `Routines` (collapsible, open by default, `<done> / <total> done`), `Quests` (collapsible, **closed** by default, `<done> / <total> done`; the total counts every row that is not replaced, the epic and the hidden quest included, so it is the random slots plus 1 on the day the epic was drawn: read it, don't assert a fixed number), `THAT NIGHT` (night card, whose right side reads `<time> · <n> words`, or `Nothing written` + `Write about this day`, shown only for today and earlier days), `Done this day for another day`, `Spending, penalties, skips`, `Other ratings this day`, `Body` (only when a day setting exists). Row marks: check for done, ring for open, dash for replaced / swapped / rerolled, cross for cancelled / skipped / missed.
- `cal-entries` the book button and the `All journal entries` card (`N entries, newest first`, or `Nothing written yet`) both open [the entries page](./journal-entries.md).
- `cal-missed` a routine nobody did reads `Did not finish` with a clay `-<penalty>` pill in the **Routines** section of its due day's sheet; the pill is the **running total** of its charges (11 + 16 + 21 = `-48` for a 21-point routine after all three rounds), while the coin pill of the due day holds only the round-1 charge (`-11 coins`) and rounds 2 and 3 sit under the later days' `Spending, penalties, skips`. Its `skip` ledger row (0 points) is dated due day + 3, not the next day, and appears on that later day's sheet. A routine that does not count toward clearing the day is never charged, so it shows no pill. The Calendar page itself has no `Did not finish` card any more (removed in commit c55f6ab).
- Ratings summary: the `Ratings` page no longer hangs off the Calendar; it is on [Trends](./trends.md).

## How to get to it (user POV)

- Tap the Calendar tab (x=160, y=880 pt); tap a day; tap the round `‹ ›` buttons to change month; tap the book button (about 402, 99 pt) or the `All journal entries` card.

## Driving it with the simulator

Preconditions:

- `V up --fresh`, then complete one quest and rate it +2 ([today-complete](./today-complete.md)).

- **Grid.** Tap Calendar. The grid shows the current month; the app's day has an accent ring and carries a tier-coloured dot per completed random quest (an `Easy` quest gives a blue dot, a `Medium` one yellow). The legend chips read `Trivial`, `Easy`, `Medium`, `Hard`, `Journal, darker is longer`, `Routines`, `Hidden`, `Epic week`. A fresh store shows `All journal entries — Nothing written yet`.
- **Detail.** Tap the app day's cell (locate it from the screenshot; Sunday the 4th sat at about 388, 255 pt). The sheet header shows the weekday in script over the date and the pills (`+125 coins` was 100 grant + 25 quest). The `Quests` header shows `1 / 3 done`; tap it to open the section, where the completed quest shows `+<points>` and `Rated +2`.
- **Cross-check.** `V sql "select ZDAYKEY, sum(ZPOINTS) from ZLEDGERENTRY group by ZDAYKEY"` for that day equals the coin pill (spending, penalties, skips and the grant included).
- **Night card.** With nothing written the card is an outlined `Nothing written` with `Write about this day →` (opens the editor for that day; `Done` there returns to the sheet). After writing, it becomes a dark card `THAT NIGHT <time> · <n> words` with a 3-line excerpt (text and answers, not the questions) and `Read the whole entry` (opens the reader, see [journal-entries](./journal-entries.md)). The pencil appears under that day's cell once the sheet closes.
- **Close.** Swipe the sheet down (from about y=300 to 900 pt); there is nothing to tap.
- **Missed routine (driven).** Needs a fixed-day routine open on a past day: on a Wednesday store `Take out the trash` is done, so first give another routine a due day (Library → `Change days`, see [library](./library.md); a Tue / Thu schedule makes it due on Thu D0+1). `V day 4` (the app day is D0+4) judges D0+3: open the Thursday cell (about 220, 319 pt in the second row; it carries no mark): header `-11 coins`, `normal day`, `Routines 0 / 2 done` with `Send job applications` `Did not finish` `-13` and `Take out the trash` `Did not finish` `-48` (cross icons), `THAT NIGHT` `Nothing written` + `Write about this day →`, and `Spending, penalties, skips` with `Penalty` `Take out the trash — overdue day 1` `-11`. `V ledger` shows the three `penalty` rows (10-08, 10-09, 10-10) and the `skip` row dated 10-11. For an occurrence due on D0 itself the same state is `V day 3`.

## Gotchas

- The coin pill for the first day includes the 100-coin starting grant, because the grant is dated that day (driven: `+119 coins` = 100 − 20 redeemed + 5 + 6 + 28; `V sql` agreed).
- The epic band marks the week the epic was completed in, not the week it was drawn, and a tick needs at least one clear-gating, non-replaced routine due that day with none skipped or done late. `Seed 60 journal days` also writes done quests and routines, so it produces dots and ticks too, not only pencils.
- Day dots show only for days with generated data; days after today are dimmed (not blank) and cannot be opened.
- A calendar cell's accessibility value says only `journal entry`, so the three pencil shades are not distinguishable by label: prove them with a zoomed screenshot (opacity about 0.32 / 0.62 / 1) plus the word count from the store.
- Section state (`Routines` open, `Quests` closed) is held for the session; re-opening a sheet keeps what you toggled.
- Time-travelled days appear as ordinary days.
- A month with rich history for screenshots: Debug → `Seed 60 journal days` (simulator only; see [trends](./trends.md)) writes entries and day settings, or restore a snapshot through Settings → Restore from JSON…. Both leave fixture data behind, so `V up --fresh` afterwards.
- At accessibility sizes the month grid is capped at `xxxLarge` by design; the legend, header and entries card scale fully.
