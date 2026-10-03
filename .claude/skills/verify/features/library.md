# Library

Settings → Library lists quest and routine templates, grouped by difficulty (quests) or schedule (routines), with search. Opening one shows its ratings and notes and lets the user rate it again or add a note. Ratings and notes are append-only and dated.

## Sub-features

- `lib-switch` the `Quests` / `Routines` pill picker (accessibility label `Library`) switches the list.
- `lib-tiers` quest tiers `Trivial`, `Easy`, `Medium`, `Hard`, `Epic` start collapsed with a count each (the counts equal Debug's "Quests by difficulty"); the open set survives a relaunch (`library.openQuestTiers`).
- `lib-search` pulling the list down reveals a search field; a match opens its section and the header taps do nothing while searching.
- `lib-detail` a row opens a detail page: summary card, `How do you feel about it now?` rating row, `Add a note`, then `Notes` and `Ratings`.
- `lib-rate` a rating tapped on the detail page appends a row; the old ones stay.
- `lib-note` `Add a note` appends a note; the old rows survive.

## How to get to it (user POV)

- Tap the Settings tab → Library (first row); pull down for search; tap a row; back with the round button top-left.

## Driving it with the simulator

Preconditions: `V up --fresh`, then complete and rate one quest so it has a rating.

- **List.** Tap the Settings tab (x=309, y=880 pt), then Library (about 220, 247 pt at the top of Settings). The quest list shows its five tier headers collapsed with counts `16 / 18 / 17 / 18 / 7`; the pill picker is below the title. Routines (picker, x=320) shows its groups (`Set days`, `Flexible`, `Monthly or longer`, `Lighter versions`, and `Every few days` / `Not scheduled` when non-empty) open, each row with a summary pill and a week strip; the detail page has a `Schedule` card.
- **Search.** Swipe down from about y=400 to y=700 pt, tap the field (about 220, 190 pt), type `sunset`. The `Easy` section opens and shows `Watch a sunset` with a `+2` badge (the latest rating). `X` top-right closes search.
- **Detail.** Tap the row (about 220, 267 pt with the keyboard up). The page shows the `Easy` pill, the rating row with the right-most thumb filled and `Latest: Loved it, <day>. Rating again adds a new entry; the old ones stay.`, `Add a note`, and `Ratings` with `Loved it`, `+2`, `<day> · right after doing it`.
- **Rate again.** Tap the middle `–` button (about 220, 277 pt): a new row appears, `Latest: Fine`. `V sql "select ZRATING, ZTARGETKINDRAW, ZQUESTID is not null from ZQUESTRATING order by Z_PK"` shows the original `2 | quest | 1` and a new `0 | quest | 0`: a rating given here has no `ZQUESTID`.
- **Note.** Tap the field (`What worked, what didn't`, about 220, 430 pt), type a note and wait for the text to land before tapping `Add note` (about 364, 493 pt; it is disabled while the field is empty). The field clears and keeps focus, and a `Notes` section appears. `V sql "select ZCOMMENT, ZTEXTSNAPSHOT from ZQUESTCOMMENT order by Z_PK"` returns it, and a second note adds a second row. On the list the row now shows a `2 notes` pill and the badge `0`.

## Gotchas

- Notes and ratings are never overwritten: assert row counts grow, not that a row changed.
- The control tool's `text` returns before every character is typed: a tap on `Add note` straight after it saved `second` and left `note` in the field. Screenshot (or wait a second) between typing and tapping.
- Search filters quest and routine text, not notes.
- Affinity (the mean of the last three ratings) feeds the draw; prove it with `swift test`, not here.
