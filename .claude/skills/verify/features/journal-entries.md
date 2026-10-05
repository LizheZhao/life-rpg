# Journal entries and reader

The all-entries page lists every written night by month, with search; a row opens the reader (previous and next night, share, edit). Elsewhere the journal shows as the calendar pencil and the day sheet's night card.

## Sub-features

- `jl-entry-points` the page opens from the Calendar's book button and its `All journal entries` card, and from Trends' `All journal entries` row (shown as soon as any entry exists, locked or not).
- `jl-list` the title `Journal`, a script subtitle `N entries · M night streak` (`1 entry`; the streak is omitted at 0; `No entries yet` when empty), month sections (`OCTOBER`, or `OCTOBER 2025` for another year) of rows: day number, weekday, a 2-line preview (80 characters), `N words`, and a capsule `1 prompt` / `N prompts` only when the entry has prompts.
- `jl-tonight` a dark `Tonight, in progress` card (`N words · keep going`) appears only while today's entry is a draft and no search is active; it opens the editor.
- `jl-search` the magnifier (top right) reveals a field `Search your writing` with a `Clear search` x; it matches text, answers and prompt questions (case and diacritics ignored, whitespace trimmed); empty result `No entries match “<query>”.` (curly quotes); with no entries `Nothing written yet.`. While a query is active the Tonight card is hidden. Autocapitalisation and autocorrection are off.
- `jl-reader` a row opens a full-screen reader: `Back`, `Share` and `Edit` (a pencil that opens the editor for that day), the heading `Sunday, October 4 · 10:35 PM` (the time is the last update), chips (`8 words`, `1 quest done`, `normal day`), then the blocks; an unanswered prompt reads `Not answered`. Previous / next date pills (`Sep 30`) appear only for days that have an entry. Only `Back` closes it (no swipe).
- `jl-sent` the reader's caption says `Sent to Apple Journal, <date>, <time>` once the day was handed off, or `Edited since it was sent; the copy in Apple Journal is the earlier version` when the text changed afterwards.
- `jl-marks` the Calendar pencil and the day sheet's night card read the same entries (see [calendar](./calendar.md)).

## How to get to it (user POV)

- Calendar tab → book button (about 402, 99 pt) or the `All journal entries` card; Trends tab → `All journal entries`; a day sheet's `Read the whole entry`.

## Driving it with the simulator

Preconditions: `V up --fresh`. To have many entries without typing them, Settings → Debug → `Trends fixture (simulator only)` → `Seed 60 journal days` writes about 51 entries (one night in seven is skipped), with day settings, quests and routines to go with them. Run `V up --fresh` afterwards: none of it is real use.

- **List.** Calendar → book button. The page reads `52 entries · 3 night streak` (51 seeded plus one written by hand) with `OCTOBER` and `SEPTEMBER` sections, newest first; the count equals `V sql "select count(*) from ZJOURNALENTRY"`. Rows show `Hello world today / 8 words / 3 prompts` and `Today I feel fine. Called a friend… / 53 words`. With today's entry marked done there is no Tonight card.
- **Search.** Tap the magnifier (about 398, 92 pt), type `zzzq`: `No entries match “zzzq”.` with the subtitle unchanged. Tap the x (`Clear search`) or the magnifier again to leave; the query clears.
- **Reader.** Tap a row (not driven from the list this pass; driven from a day sheet's night card): the heading, chips and blocks as above. `Back` is the round button at about 42, 92 pt.
- **Sent line (not driven).** Debug → `Journal hand-off`; see [journal-editor](./journal-editor.md).
- **Store.** `ZJOURNALENTRY` columns: `ZDAYKEY`, `ZBLOCKSJSON`, `ZCREATEDAT`, `ZUPDATEDAT`, `ZDONEAT` (NULL for a draft). The word count is derived, never stored: count words of text blocks and prompt answers (not the questions) to compare with `N words`.

## Gotchas

- The fixture only writes past days and leaves `ZDONEAT` NULL, so the Tonight card needs a draft written by hand (type something in today's editor and press `Close`).
- The Journal page's streak right after seeding is 2 or 3: one night in seven is skipped.
- The reader is a full-screen cover; there is no swipe-down. Neighbour pills exist only for days that have an entry.
- The sent log lives in UserDefaults (`journalSentLog`), not in the store, so `V sql` cannot see it.
- Real Apple Journal creation, the 05:00 automation, the Share sheet's contents and Chinese rendering need a device or a system language change.
