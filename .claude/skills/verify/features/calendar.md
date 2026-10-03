# Calendar and day detail

The Calendar tab shows a month grid: up to three dots per day coloured by the tier of each random quest done, a tick for cleared routines, a violet star for the hidden quest, and a soft band behind an epic week. Below it sit a legend, a `Did not finish` card when routines were missed in the shown month, and a `Ratings` row. Tapping a day opens a sheet of cards with that day's net points, body data, routines due and quests, with ratings.

## Sub-features

- `cal-grid` month grid with today ringed and marks for days with data; days after today are dimmed and not tappable.
- `cal-nav` previous / next month chevrons (next is disabled on the current month).
- `cal-detail` day sheet: Net points, Body, Routines due, Quests with `Done <time>` / `Rated <n>`; further cards appear only when they have content.
- `cal-missed` the `Did not finish <n>` card expands to the missed routines (title, `Due <day>`, clay `−<penalty>`); a row opens that day's sheet, where the routine reads `Did not finish`.
- `cal-summary` the `Ratings` row under the legend (`What has been landing well lately`) pushes the rating summary: a pill picker `7 days` / `30 days` / `90 days` / `All` (default 30), a `Since <date>` header and one row per rated item with its mean and `<n>×`.

## How to get to it (user POV)

- Tap the Calendar tab; tap a day with a dot; tap the round `‹ ›` buttons to change month (`This month` pill returns); tap the `Did not finish` card; tap the `Ratings` row under the legend (back with the round button top-left, about 42, 84 pt).

## Driving it with the simulator

Preconditions:

- `V up --fresh`, then complete one quest and rate it +2 ([today-complete](./today-complete.md)).

- **Grid.** Tap Calendar (x=189 pt, y=880 pt). The grid shows the current month; the app's day has an accent ring and carries a tier-coloured dot per completed random quest (an `Easy` quest gives a blue dot). The legend chips read `Trivial`, `Easy`, `Medium`, `Hard`, `Routines`, `Hidden`, `Epic week`. A fresh store has no `Did not finish` card.
- **Detail.** Tap that day (locate its cell from the screenshot; a Saturday sits at about x=332 pt, y=284 pt in a month whose first row holds the 1st to 4th). The sheet title is the date (`Saturday, October 3`) and the day key sits on the net-points card. `Net points` is the sum of **that day's** ledger rows (spending, penalties, skips and the grant included), not a running balance. The completed quest shows `+<points>` and `Rated +2`.
- **Cross-check.** `V sql "select ZDAYKEY, sum(ZPOINTS) from ZLEDGERENTRY group by ZDAYKEY"` for that day equals `Net points`.
- **Close.** Tap `Done` (x=383 pt, y=104 pt); wait a second before the next tap.
- **Ratings.** Tap the `Ratings` row (about 220, 774 pt). The page shows the pill picker and one row per rated item, e.g. `Watch a sunset +2.0 1×`.
- **Did not finish.** After `V day 2` over a day with open routines, the Calendar shows `Did not finish <n>`; `<n>` equals the `skip` rows in `V ledger` due in the shown month (6 after walking a Thursday-to-Sunday gap with 6 routines due).

## Gotchas

- Net points for the first day includes the 100-coin starting grant, because the grant is dated that day.
- Day dots show only for days with generated data; days after today are dimmed (not blank) and cannot be opened.
- Time-travelled days appear as ordinary days.
- A month with rich history for screenshots can be restored through Settings → Restore from JSON… (the app's own import path) from a hand-built snapshot copied into the sim's `File Provider Storage` folder; the picker opens on Browse → On My iPhone, not Recents. The restore replaces every history table, so `V up --fresh` afterwards.
- At accessibility sizes the month grid is capped at `xxxLarge` by design; the legend, header and Ratings row scale fully.
