# Journal entries and reader

The all-entries page lists every written night by month, with search; a row opens the reader (previous and next night, share, edit). Elsewhere the journal shows as the calendar pencil and the day sheet's night card.

## Sub-features

- `jl-entry-points` the page opens from the Calendar's `All journal entries` card (the header book button is gone) and from Trends' `All journal entries` row (shown as soon as any entry exists, locked or not).
- `jl-list` the title `Journal`, a script subtitle `N entries · M night streak` (`1 entry`; the streak is omitted at 0; `No entries yet` when empty), month sections (`OCTOBER`, or `OCTOBER 2025` for another year) of rows: day number, weekday, a 2-line preview (80 characters), `N words`, and a capsule `1 prompt` / `N prompts` only when the entry has prompts.
- `jl-tonight` a dark draft card (`Tonight, in progress` from 20:00 to 05:00, `Today, in progress` by day; detail `N words · keep going`) appears only while today's entry is a non-empty draft (prompts with no answer, or whitespace, do not count) that is not done (see the Gotchas: closing the editor marks it), and no search is active (during a search today's draft shows as an ordinary row); it opens the editor. While the card shows, today is left out of the rows but still counted in the subtitle. Driven by day: `Today, in progress` / `2 words · keep going`, subtitle `1 entry · 1 night streak`.
- `jl-search` the magnifier (top right) reveals a field `Search your writing` (the magnifier's accessibility label is `Search entries`, selected while searching) with a `Clear search` x that exists only while the query is non-empty and only clears it (the field stays open; the magnifier is what closes it and also clears the query); it matches text, answers and prompt questions (case and diacritics ignored, whitespace trimmed); empty result `No entries match “<query>”.` (curly quotes, also when there are no entries at all but a query is active); with no entries and no query `Nothing written yet.`. While a query is active the Tonight card is hidden. Autocapitalisation and autocorrection are off.
- `jl-reader` a row opens a full-screen reader: `Back`, `Share` and `Edit` (a pencil that opens the editor for that day), the heading `Sunday, October 4 · 10:35 PM` (the time is the last update), chips (`8 words`, `1 quest done`, `normal day`), then the blocks; an unanswered prompt reads `Not answered`. Previous / next date pills show the date of the nearest older / newer day that has an entry (`Sep 30`, not the adjacent calendar day, no words `Previous` / `Next`), appear only when there is one, and swap the day in place (chips and sent line re-read). `Share` is drawn only when the day has an entry, `Edit` always; if the entry was cleared in the editor the reader falls back to a date-only heading with `Nothing is written for this day.`. Chips come in the order words, quests done, tier and drop the quests chip at 0 and the tier chip when the day has no day setting. Only `Back` closes it (no swipe).
- `jl-sent` the reader's caption says `Sent to Apple Journal, <date>, <time>` once the day was handed off, or `Edited since sending` when the text changed afterwards. The line sits under the chips, the date and time are those of the hand-off (in the user's locale; the heading time is fixed to en_US), only the Debug / Shortcut hand-off records a send (the reader's Share does not), and a whitespace-only edit stays `Sent` because the comparison trims each block.
- `jl-marks` the Calendar pencil and the day sheet's night card read the same entries (see [calendar](./calendar.md)).

## How to get to it (user POV)

- Calendar tab → the `All journal entries` card; Trends tab → `All journal entries`; a day sheet's `Read` (to the reader of that one day).

## Driving it with the simulator

Preconditions: `V up --fresh`. To have many entries without typing them, Settings → Debug → `Trends fixture (simulator only)` → `Seed 60 journal days` writes about 51 entries (one night in seven is skipped), with day settings, quests and routines to go with them. Run `V up --fresh` afterwards: none of it is real use.

- **List (driven again on 2026-10-07 with one done entry).** The page read `1 entry · 1 night streak` with an `OCTOBER` section and a row `7 / Wed / hello world today / 8 words / 1 prompt`, no Tonight card (the entry was done). Calendar → `All journal entries`. An earlier pass with the fixture: the page reads `52 entries · 3 night streak` (51 seeded plus one written by hand) with `OCTOBER` and `SEPTEMBER` sections, newest first; the count equals `V sql "select count(*) from ZJOURNALENTRY"`. Rows show `Hello world today / 8 words / 3 prompts` and `Today I feel fine. Called a friend… / 53 words`. With today's entry marked done there is no Tonight card.
- **Search.** Tap the magnifier (about 398, 92 pt), type `zzzq`: `No entries match “zzzq”.` with the subtitle unchanged. Tap the x (about 402, 253 pt): the text clears and the field **stays open** (`Search your writing`, rows back). Tap the magnifier again to close it.
- **Reader.** Tap a row (about 220, 298 pt for the first; driven from the list on 2026-10-07): heading `Wednesday, October 7 · 10:01 AM`, chips `8 words`, `3 quests done`, `normal day`, the text block and the question with its answer, `Share` and the pencil at the top right, no previous / next pills (one entry), no sent line. `Back` is the round button at about 42, 92 pt.
- **Sent line (not driven).** Debug → `Journal hand-off`; see [journal-editor](./journal-editor.md). Settings → `Journal & reminders` (one page since c1a782b; `Journal` was a page of its own before) shows the same log as one status line in its `Apple Journal` section, `Nothing sent yet` (seen 2026-10-12) or `Last sent: <date>, <time>`, above the `Set up once` steps for the Shortcut; it is a second place to check a hand-off without opening the reader.
- **Store.** `ZJOURNALENTRY` columns: `ZDAYKEY`, `ZBLOCKSJSON`, `ZCREATEDAT`, `ZUPDATEDAT`, `ZDONEAT` (NULL for a draft). The word count is derived, never stored: count words of text blocks and prompt answers (not the questions) to compare with `N words`.

## Gotchas

- The fixture only writes past days and leaves `ZDONEAT` NULL, so the Tonight card needs a draft written by hand. Leaving the editor now marks an entry with writing done (`Done`, or any other way out), so a draft survives only when the app stops with the editor open: type, wait 2 s for the autosave, then `V relaunch` (from source, not driven).
- The Journal page's streak right after seeding is 2 or 3: one night in seven is skipped.
- The reader is a full-screen cover; there is no swipe-down. Neighbour pills exist only for days that have an entry.
- The sent log lives in UserDefaults (`journalSentLog`), not in the store, so `V sql` cannot see it.
- Real Apple Journal creation, the 05:00 automation, the Share sheet's contents and Chinese rendering need a device or a system language change.
