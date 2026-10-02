# Calendar and day detail

The Calendar tab shows a month grid with a coloured dot per day type (Random, Routines, Hidden star, Epic week shading). Tapping a day opens a sheet with that day's net points, body data, routines due and quests, with ratings.

## Sub-features

- `cal-grid` month grid with today highlighted and marks for days with data.
- `cal-nav` previous / next month chevrons.
- `cal-detail` day sheet: Net points, Body, Routines due, Quests with `Done <time>` / `Rated <n>`.
- `cal-summary` the speech-bubble toolbar button opens the rating summary.

## How to get to it (user POV)

- Tap the Calendar tab; tap a day with a dot; tap `‹ ›` to change month; tap the top-right bubble for ratings.

## Driving it with the simulator

Preconditions:

- `V up --fresh`, then complete one quest and rate it +2 ([today-complete](./today-complete.md)).

- **Grid.** Tap Calendar (x=143 pt). The grid shows the current month; the app's day is highlighted and carries a green (Random) dot.
- **Detail.** Tap that day (about x=220 pt, y=245 pt for the 1st in a month starting Thursday — locate it from the screenshot). The sheet title is the day key. `Net points` equals the balance up to that day (the grant is included on the first day). The completed quest shows `+<points>` and `Rated +2`.
- **Cross-check.** `V ledger` summed for that day equals `Net points`.
- **Close.** Tap `Done` (x=383 pt, y=104 pt); wait a second before the next tap.

## Gotchas

- Net points for the first day includes the 100-coin starting grant.
- Day dots show only for days with generated data; future days in the grid are blank.
- Time-travelled days appear as ordinary days.
