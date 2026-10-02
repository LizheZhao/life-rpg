# Calendar and day detail

The Calendar tab shows a month grid: up to three dots per day coloured by the tier of each random quest done, a tick for cleared routines, a violet star for the hidden quest, and a soft band behind an epic week. Tapping a day opens a sheet of cards with that day's net points, body data, routines due and quests, with ratings.

## Sub-features

- `cal-grid` month grid with today highlighted and marks for days with data.
- `cal-nav` previous / next month chevrons.
- `cal-detail` day sheet: Net points, Body, Routines due, Quests with `Done <time>` / `Rated <n>`.
- `cal-summary` the `Ratings` row under the legend opens the rating summary (pill window picker 7 / 30 / 90 / All).

## How to get to it (user POV)

- Tap the Calendar tab; tap a day with a dot; tap the round `‹ ›` buttons to change month (`This month` pill returns); tap the `Ratings` row under the legend.

## Driving it with the simulator

Preconditions:

- `V up --fresh`, then complete one quest and rate it +2 ([today-complete](./today-complete.md)).

- **Grid.** Tap Calendar (x=143 pt). The grid shows the current month; the app's day has an accent ring and carries a tier-coloured dot per completed random quest.
- **Detail.** Tap that day (about x=220 pt, y=245 pt for the 1st in a month starting Thursday — locate it from the screenshot). The sheet title is the date (`Friday, October 2`) and the day key sits on the net-points card. `Net points` equals the balance up to that day (the grant is included on the first day). The completed quest shows `+<points>` and `Rated +2`.
- **Cross-check.** `V ledger` summed for that day equals `Net points`.
- **Close.** Tap `Done` (x=383 pt, y=104 pt); wait a second before the next tap.

## Gotchas

- Net points for the first day includes the 100-coin starting grant.
- Day dots show only for days with generated data; future days in the grid are blank.
- Time-travelled days appear as ordinary days.
- A month with rich history for screenshots can be restored through Settings → Restore from JSON… (the app's own import path) from a hand-built snapshot copied into the sim's `File Provider Storage` folder; it then appears under Browse → On My iPhone, not Recents. The restore replaces every history table, so `V up --fresh` afterwards.
- At accessibility sizes the month grid is capped at `xxxLarge` by design; the legend, header and Ratings row scale fully.
