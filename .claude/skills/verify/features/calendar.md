# Calendar and day detail

The Calendar tab shows a month grid: up to three dots per day coloured by the tier of each random quest done, then on one row a journal pencil, a routines tick and a violet hidden-quest star, and a soft band behind an epic week. Below it sit a legend and an `All journal entries` card; a round book button at the top right opens the same list. Tapping a day opens a bottom sheet with that day's net coins, routines, quests, the night's journal entry, spending and ratings.

## Sub-features

- `cal-grid` month grid with today ringed and marks for days with data; days after today are dimmed and not tappable, and an empty day does not open.
- `cal-nav` previous / next month chevrons (next is disabled on the current month; a `This month` pill returns from another month).
- `cal-marks` dots (completed, non-replaced, non-epic, non-hidden random quests; the easiest kept, a trivial group counts once), pencil (a journal entry that day, three shades by word count: under 100, 100–299, 300+; the legend chip reads `Journal, darker is longer`), tick (every clear-gating routine due that day done on its due day or ahead), star (hidden quest done).
- `cal-detail` the day sheet (720 pt detent, drag indicator, **no `Done` button**: swipe down to close). Order: header (weekday, date, a `+N coins` pill that is the sum of that day's ledger rows, a tier pill such as `normal day`), `Routines` (collapsible, open by default, `<done> / <total> done`), `Quests` (collapsible, **closed** by default, `<done> / <total> done`), `THAT NIGHT` (night card or `Nothing written` + `Write about this day`), `Done this day for another day`, `Spending, penalties, skips`, `Other ratings this day`, `Body` (only when a day setting exists). Row marks: check for done, ring for open, dash for replaced / swapped / rerolled, cross for cancelled / skipped / missed.
- `cal-entries` the book button and the `All journal entries` card (`N entries, newest first`, or `Nothing written yet`) both open [the entries page](./journal-entries.md).
- `cal-missed` a routine nobody did reads `Did not finish` with a clay `-<penalty>` pill in the **Routines** section of its due day's sheet, and its `skip` ledger row (0 points, dated the next day) is under `Spending, penalties, skips`. The Calendar page itself has no `Did not finish` card any more (removed in commit c55f6ab).
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
- **Missed routine (from source, not driven this pass).** `V day 2` over a day with open routines, then open that past day: the routine row reads `Did not finish` with the cross and a clay `-<penalty>`; `V ledger` shows the `skip` row dated the next day.

## Gotchas

- The coin pill for the first day includes the 100-coin starting grant, because the grant is dated that day.
- Day dots show only for days with generated data; days after today are dimmed (not blank) and cannot be opened.
- A calendar cell's accessibility value says only `journal entry`, so the three pencil shades are not distinguishable by label: prove them with a zoomed screenshot (opacity about 0.32 / 0.62 / 1) plus the word count from the store.
- Section state (`Routines` open, `Quests` closed) is held for the session; re-opening a sheet keeps what you toggled.
- Time-travelled days appear as ordinary days.
- A month with rich history for screenshots: Debug → `Seed 60 journal days` (simulator only; see [trends](./trends.md)) writes entries and day settings, or restore a snapshot through Settings → Restore from JSON…. Both leave fixture data behind, so `V up --fresh` afterwards.
- At accessibility sizes the month grid is capped at `xxxLarge` by design; the legend, header and entries card scale fully.
