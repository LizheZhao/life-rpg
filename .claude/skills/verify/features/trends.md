# Trends

The Trends tab turns the journal and the day's results into patterns. It is locked until seven distinct days have a written entry (counted over all time); then it shows a Weeks / Months / Year picker and a stack of cards.

## Sub-features

- `tr-lock` the locked page: subtitle `unlocks after 7 nights`, a dark card `N of 7 nights written` with the line `Unlocks after 7 days of writing. Short entries count.` and seven tiles numbered `1` to `7` (they count nights, not weekdays), `Write tonight's entry` (from 20:00 to 05:00, so also 00:00–04:59; `Write today's entry` by day, same clock as the editor), a `WHAT YOU'LL SEE HERE` list of four previews (`Words that defined the month`, `Favorite quests`, `Low energy days vs. what got done`, `Writing streak and usual hour`), a `Ratings` row, and an `All journal entries` row once any entry exists. A written day is an entry with non-whitespace text in a text block or an answer.
- `tr-head` once unlocked: the picker (`Weeks` / `Months` / `Year`, default Months), the title, a script subtitle `October · 3 entries`, and previous / next chevrons (previous is enabled only when an entry exists before the period, next is disabled at 30% opacity whenever the period holds today; both are hidden when there is nowhere to go either way, e.g. `Year` with every entry in this year).
- `tr-tiles` `words`, `day streak` (all-time, ending today or yesterday), `usual hour` (the modal local hour of an entry's creation time; `—` with fewer than 5 entries in the period).
- `tr-words` `Words per day`: one bar per day of the whole period (a month always draws 28–31 slots, future days as 3 pt stubs, so the last axis label is the month end, `Oct 31`, not today), `avg N`, the darkest bars at or above the nearest-rank 90th percentile of written days, axis dates first / middle / last. A period with no written entry shows `Nothing written this month.` (week / year) instead of this chart and the calendar; the tiles stay.
- `tr-about` `What this month was about` (subtitle `Words that stood out versus your other months`; needs entries in another period of the same kind plus entries in the shown one) or, without one, `Most used words` (`Plain counts until another month has entries`); up to five rows, minimum count 2 (the card is absent when no word reaches it), and a phrase repeated three times or more (`light version`) can be a row too.
- `tr-calendar` `Writing calendar`: a grid of day tiles in three shades by word count (under 100, 100–299, 300+).
- `tr-fav` `Favorite quests` (caption `Done most and rated best this month`): the top three of the shown period by times done, then mean rating, then text, counting quests, routines and ad-hoc picks; each row `N times` or `N times · light version M`, stars are the period's mean rating shifted by three and clamped to 1–5; absent when nothing was done in the period.
- `tr-ratings` the `Ratings` row (caption `Your library, best rated first`) pushes the Library already on its `Rated best` order (see `lib-rated` in [library](./library.md)): a flat list, best mean first, each rated row with a pill like `+1.0 · 1×`. The old rating summary page (`7 days` / `30 days` / `90 days` / `All`, `ratingSummaryDays`) is gone, and so is its window; the row is on the locked page too. Not driven.
- `tr-energy` `Low energy days` (`vs quests done`, subtitle `Days you set "very low" against how much still got done`, legend `normal day` / `low energy day`): only when the period has a low or very-low day (driven: one `low` day gave the card with seven bars); its footer (`On low days you still finished N% of a normal day.`) needs at least 3 low and 3 normal days and normal days that earned points.
- `tr-grateful` `Grateful for, most often`: answers to the `Grateful for` chip only, split on commas, `and`, `;`, `、`, `，`, `；`, `和`, newlines and sentence ends; items over 40 characters are dropped, at most 7 chips, counted within the shown period only.
- `tr-year` `Year at a glance`: twelve months of today's calendar year, shade 1 for 1–9 entries, 2 for 10–21, 3 for 22 or more; hidden when today's year has no entry at all.
- `tr-list` the last row, `All journal entries` (see [journal-entries](./journal-entries.md)).

## How to get to it (user POV)

- Tap the Trends tab (x=220, y=880 pt, third of five).

## Driving it with the simulator

Preconditions: `V up --fresh`.

- **Locked.** Tap Trends. After writing one entry by hand the card reads `1 of 7 nights written` with the first tile (`1`) lit (seen again 2026-10-12) and `Write tonight's entry`; the previews and `Ratings` follow, and `All journal entries` appears. `V sql "select count(distinct ZDAYKEY) from ZJOURNALENTRY"` is the number on the card, unless a row holds only whitespace (it shows the `All journal entries` row but does not count as written).
- **Unlock.** Settings → Debug → `Trends fixture (simulator only)` → `Seed 60 journal days` (about 133, 245 pt when Debug is scrolled to that section; `Seed a year` writes about 313). The note reads `Wrote 51 entries, 60 day settings, 167 quests and 105 routines before <today>.` Return to Trends.
- **Cards.** Observed order: tiles, `Words per day`, `What this month was about`, `Writing calendar`, `Favorite quests`, `Ratings`, (`Low energy days` when present), `Grateful for, most often`, `Year at a glance`, `All journal entries`. Observed values depend on the date, so compute them from the app day: on 2026-10-07 with the fixture only (no hand-written entry) `October · 5 entries`, `523 words`, `2 day streak` (the seed skips the nights where `back % 7 == 3`, here 10-04), `usual hour 9 PM`, `avg 105`; an earlier pass with one hand-written entry on top read `October · 3 entries`, `128 words`, `3 day streak`, `usual hour —`.
- **Cross-check.** Entries per month: `V sql "select substr(ZDAYKEY,1,7), count(*) from ZJOURNALENTRY group by 1"` (23, 26 and 3 gave August and September shade 3, October shade 1 on `Year at a glance`). Words per day: the app's tokenizer is not whitespace splitting, so a SQL count (`json_each` over `ZBLOCKSJSON`, split on spaces, empty answers counted as 0) matches only approximately (126 against 128 observed); assert the order of magnitude, not the digit. Low-energy days: `select ZTIERRAW, count(*) from ZDAILYCONTEXT where ZDAYKEY like '2026-10%' group by 1`; no low day means no `Low energy days` card.

## Gotchas

- The seed is simulator-only and deterministic: pressing it twice rewrites the same rows. It skips every seventh night, so the streak right after seeding is short.
- Months is the calendar month and Weeks runs Monday to Sunday, so counts differ from "last 30 days"; the chart and calendar always draw every day of the period, so early in a month only the number of written days is small, not the number of slots.
- The page builds in a task: wait a moment after a tab or period switch.
- The year seed writes `DailyContext`, `DailyQuest`, `RoutineOccurrence` and `QuestRating` rows too: those are fixture data, not app use. Run `V up --fresh` afterwards.
- The picker is hidden while locked.
- Real `usual hour` and a live streak across days need entries written over several real days; Chinese word tokenisation needs the system language set to Chinese.
