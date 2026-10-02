# Library

Settings → Library lists quest and routine templates, grouped by difficulty, with search. Opening one shows its ratings and notes and lets the user add a note. Ratings and notes are append-only and dated.

## Sub-features

- `lib-switch` the `Library` picker switches Quests / Routines.
- `lib-search` the search field filters by text.
- `lib-detail` a row opens a detail with `Notes` and `Ratings`.
- `lib-note` `Add a note` appends a note; the old rows survive.

## How to get to it (user POV)

- Tap the Settings tab → Library; pull down for search; tap a row.

## Driving it with the simulator

Preconditions: `V up --fresh`, then complete and rate one quest so it has a rating.

- **List.** Tap the Settings tab (x=309, y=880), then Library (y=236). The quest list shows with difficulty section headers; the segmented picker is at the top.
- **Detail (not yet driven).** Tap the rated quest's row. `Ratings` lists the +2 you logged.
- **Note (not yet driven).** Type in `What worked, what didn't`, tap `Add note`. `V sql "select ZCOMMENT, ZTEXTSNAPSHOT from ZQUESTCOMMENT"` returns it, and a second note adds a second row.

## Gotchas

- Notes and ratings are never overwritten: assert row counts grow, not that a row changed.
- Affinity (the mean of the last three ratings) feeds the draw; prove it with `swift test`, not here.
- Not driven in the authoring run; written from `LifeRPG/LibraryView.swift`.
