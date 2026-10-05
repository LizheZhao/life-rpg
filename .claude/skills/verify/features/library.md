# Library

Settings → Library lists quest and routine templates, grouped by difficulty (quests) or schedule (routines), with search. Opening one shows its ratings and notes and lets the user rate it again or add a note. Ratings and notes are append-only and dated.

## Sub-features

- `lib-switch` the `Quests` / `Routines` pill picker (accessibility label `Library`) switches the list.
- `lib-tiers` quest tiers `Trivial`, `Easy`, `Medium`, `Hard`, `Epic` start collapsed with a count each (the counts equal Debug's "Quests by difficulty"); the open set survives a relaunch (`library.openQuestTiers`).
- `lib-search` pulling the list down reveals a search field; a match opens its section and the header taps do nothing while searching.
- `lib-detail` a row opens a detail page: summary card, a **Settings** card (`On` toggle; routines also get a `Pays N` stepper, step 5, minimum 5), a `Schedule` card (routines only), then `How do you feel about it now?` rating row, `Add a note`, `Notes` and `Ratings`.
- `lib-edit` the Settings card writes the library row: `On` off sets `ZISACTIVE` to 0 and the row reads `inactive`; the `Pays` stepper changes `ZBASEPOINTS` of a routine in steps of 5 (driven); the `On` switch is unreachable by tap, so its effect is from source.
- `lib-rate` a rating tapped on the detail page appends a row; the old ones stay.
- `lib-note` `Add a note` appends a note; the old rows survive.

## How to get to it (user POV)

- Tap the Settings tab → Library (first row); pull down for search; tap a row; back with the round button top-left.

## Driving it with the simulator

Preconditions: `V up --fresh`, then complete and rate one quest so it has a rating.

**Coverage note.** The quest steps below were driven before the detail page gained its Settings card, so the coordinates under `Detail`, `Rate again` and `Note` are stale by one card (about 55–110 pt lower now): re-read them from a screenshot. The Routines list, a routine detail and the `Pays` stepper were driven afterwards.

- **List.** Tap the Settings tab (x=340, y=880 pt), then Library (about 220, 247 pt at the top of Settings). The quest list shows its five tier headers collapsed with counts `16 / 18 / 17 / 18 / 7`; the pill picker is below the title. Routines (picker, x=320) shows its groups (`Set days`, `Flexible`, `Monthly or longer`, `Lighter versions`, and `Every few days` / `Not scheduled` when non-empty) open, each row with a summary pill and a week strip; the detail page has a `Schedule` card.
- **Search.** Swipe down from about y=400 to y=700 pt, tap the field (about 220, 190 pt), type `sunset`. The `Easy` section opens and shows `Watch a sunset` with a `+2` badge (the latest rating). `X` top-right closes search.
- **Detail.** Tap the row (about 220, 267 pt with the keyboard up). The page shows the `Easy` pill, the rating row with the right-most thumb filled and `Latest: Loved it, <day>. Rating again adds a new entry; the old ones stay.`, `Add a note`, and `Ratings` with `Loved it`, `+2`, `<day> · right after doing it`.
- **Rate again.** Tap the middle `–` button (about 220, 277 pt): a new row appears, `Latest: Fine`. `V sql "select ZRATING, ZTARGETKINDRAW, ZQUESTID is not null from ZQUESTRATING order by Z_PK"` shows the original `2 | quest | 1` and a new `0 | quest | 0`: a rating given here has no `ZQUESTID`.
- **Routines (driven).** Tap the `Routines` segment (about 320, 180 pt). The list shows `Set days` (4), `Flexible` (7) and below them `Monthly or longer` (2) and `Lighter versions` (7), all open; each row has a doodle, a summary pill (`Mon · Thu`, `Wed · Sat`, `Sat`, `Sun`) and an `M T W T F S S` strip with the due days filled. `Go to the office` is inactive in the seed: an `inactive` pill and a dimmed row.
- **Routine detail (driven).** Tap `Take out the trash` (about 220, 445 pt). Page title `Routine`; summary card (`Easy`); `Settings` card with `On` (`Comes up as usual.`) and `Pays 5` with a `−` / `+` stepper (`From the next time it comes due; one already on the page keeps what it was asked at.`); a `Schedule` card (`Wed · Sat`, the strip, `Comes up on Wednesday and Saturday.`, `Left undone, it costs 50% of its points at the end of the day, 75% the next day and 100% the day after, then it is skipped.`, `Weekly target 2`, `Counts toward clearing the day Yes`); then `How do you feel about it now?` and `Add a note`.
- **Pays stepper (driven).** The `+` (about 388, 363 pt) raised the routine's base points from 5 to 10: `V sql "select ZTEXT, ZBASEPOINTS, ZISACTIVE from ZROUTINETASK where ZTEXT='Take out the trash'"` returns `10`.
- **On switch (not reachable by tap).** The `On` toggle (about 382, 278 pt) did not flip under the control tool, so `ZISACTIVE=0` and the `inactive` pill after switching a row off were not reproduced; they are from source.
- **Note.** Tap the field (`What worked, what didn't`, about 220, 430 pt), type a note and wait for the text to land before tapping `Add note` (about 364, 493 pt; it is disabled while the field is empty). The field clears and keeps focus, and a `Notes` section appears. `V sql "select ZCOMMENT, ZTEXTSNAPSHOT from ZQUESTCOMMENT order by Z_PK"` returns it, and a second note adds a second row. On the list the row now shows a `2 notes` pill and the badge `0`.

## Gotchas

- Notes and ratings are never overwritten: assert row counts grow, not that a row changed.
- The control tool's `text` returns before every character is typed: a tap on `Add note` straight after it saved `second` and left `note` in the field. Screenshot (or wait a second) between typing and tapping.
- Search filters quest and routine text, not notes; while searching, header taps do nothing and the remembered open set is left alone.
- A quest rating also runs `Affinity.sync` (`ZAFFINITY` on the template follows the mean of its last three ratings); a routine rating does not.
- Switches do not respond to the control tool's tap (see [rewards](./rewards.md)); steppers, buttons and pills do.
- Return in the note field inserts a newline (it is multi-line with no submit action); only `Add note` saves.
- The Settings tab keeps a pushed page (Library, Debug …) when you switch tabs and come back; check the page before tapping a row.
- Affinity (the mean of the last three ratings) feeds the draw; prove it with `swift test`, not here.
