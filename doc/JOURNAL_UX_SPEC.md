# LifeRPG Journal: UX logic spec

Oct 4, 2026 · @Lizhe Zhao

## Data model

One `JournalEntry` per calendar day, keyed by local date. Guided and free writing are not two entry types; a prompt is a block inside the one entry's body.

```
JournalEntry {
  date: LocalDate            // primary key, one per day
  blocks: [Block]            // ordered
  status: draft | done       // done = user tapped Done at least once
  createdAt, updatedAt: Instant
  wordCount: Int             // cached, recomputed on save
}

Block =
  | Text   { id, text: String }
  | Prompt { id, question: String, answer: String,
             source: llm | fixed, fixedKey?: String }
```

Rules that follow from this shape:

- `blocks` is the whole document. Rendering is a flat vertical list; `Text` draws as a paragraph, `Prompt` draws as the question in small purple text over the answer with a purple left rule.
- A `Prompt` with an empty answer still persists, so a question pulled in and skipped stays visible as unanswered.
- `wordCount` counts `Text.text` and `Prompt.answer` only, never the question.
- `status` is cosmetic. Nothing reads it to decide editability. It drives the Today icon's dot and the "written" marker on the calendar.
- A day with zero blocks and zero characters has no row. Delete the row when the editor closes empty, so Calendar and Trends see absence, not a blank entry.
- No separate mode field. Which prompts the user had is reconstructable from the blocks.

## Entry points and open/close rules

Every entry point opens the same editor on today's entry. There is no mode question and nothing ever locks.

| Entry point | When shown | Opens |
| --- | --- | --- |
| Book icon, Today header | Always | Today's entry. Purple dot on the icon when `status == draft` and `wordCount > 0`, check mark when `done`, nothing when no row |
| "Write about today" card, Today | From 20:00 local, or once all routines and quests are cleared, until 04:00 next day | Today's entry. Card copy reads "Start writing" with no row, "Keep going · N words" with a draft, "Written · N words" when done |
| "Tonight, in progress" row, Journal list | While today has a row | Today's entry |
| Edit button, Reader | Always | That day's entry |

Open behaviour:

- Look up `JournalEntry[today]`. Missing: create an empty in-memory entry, do not persist yet. Present: load its blocks.
- Cursor lands at the end of the last block. Keyboard opens immediately.
- Day boundary is local midnight, with one exception: between 00:00 and 04:00 the editor opened from Today still targets the previous date, since the user is finishing last night. Calendar and Reader always use the true date.

Save and close:

- Autosave on every keystroke, debounced 500 ms, and on background. Persist the row the first time the entry has any character.
- `Done` sets `status = done`, saves, closes the editor, and returns to the caller. Reopening shows the same blocks, editable. The header reads "Reopened · saved".
- `Close` saves without changing status. There is no discard.
- Closing with zero characters deletes the row if one exists.

## Editor

The editor is a full-screen free-text page. Prompts are the only structure, and they only come in through the bar above the keyboard.

Layout, top to bottom: `Close` and `Done` in the header with the save state between them; the date line; the block list; the prompt bar pinned above the keyboard.

Prompt bar, left to right:

1. `Ask me something`, dark pill with a sparkle. Inserts an LLM-generated `Prompt` block (next section).
2. A thin divider.
3. Fixed chips, horizontally scrollable: `Favorite moment`, `Grateful for`, `Low energy felt like`, `Tomorrow`. Each inserts a `Prompt` with `source = fixed` and its `fixedKey`. A chip the entry already contains is shown dimmed and does nothing.
4. Word count, right aligned.

Insertion rules:

- A prompt inserts after the block the cursor is in. Cursor in the middle of a `Text` block: split it at the cursor, insert the prompt between the halves.
- After insertion the cursor moves into the new prompt's empty answer and the keyboard stays up.
- Pressing return at the end of a prompt answer creates a new `Text` block below it. The user is back in free text without doing anything.
- Backspace at the start of an empty prompt answer deletes the whole prompt block.
- A prompt's question is read-only. Long-press offers `Remove question`, which converts the block to `Text` keeping the answer.
- Two adjacent `Text` blocks merge on save. Two adjacent prompts never merge.

Save state label: `Saving…` while the debounce is pending, `Saved just now` for 10 s after a write, `Saved` after that, `Reopened · saved` on an entry that was already `done` when opened.

## LLM prompt generation

`Ask me something` sends one request and inserts one question. The question must come from today, not from a generic list.

Inputs to the request:

- Today's day type (`very low`, `low`, `normal`), routines and quests with done / skipped / light-version state, coins earned.
- The entry's current blocks as plain text, prompts rendered as `Q: … / A: …`.
- Questions already in the entry, so the model does not repeat one.
- The last three entries' questions, same reason.

Constraints in the system prompt: one question, under 15 words, second person, about something that happened today or was skipped today, no advice, no praise, never a question already listed. Return plain text only.

Client behaviour:

- The pill shows a spinner in place of the sparkle. Keyboard stays up. The user can keep typing; the prompt inserts at the cursor position captured when the pill was tapped.
- Timeout 6 s. On timeout or error, insert a fixed prompt the entry does not yet contain, in this order: `Favorite moment`, `Grateful for`, `Tomorrow`, `Low energy felt like`. Show a one-line toast, "Couldn't reach the guide, here's a standard one".
- Cap at 5 LLM prompts per entry. Past the cap the pill is dimmed with a tooltip "Enough questions for one night".
- Store `source = llm` on the block. Trends counts these separately from fixed ones.

Privacy note for the settings page: the entry text is sent to the model only when the user taps the pill, never on autosave or in the background. Put a toggle under Settings → Journal, `Send my writing with the question request`, default on. Off sends only the day's quests and the existing questions.

## Calendar, day sheet, reader, list

Calendar is the only place for looking back. Four surfaces, each one tap deeper.

**Day cell marker.** Under the quest dots, a small pen glyph when the day has a row. Fill by word count: under 100 light grey, 100 to 299 mid grey, 300 and up ink. No row, no glyph. The legend reads "Journal, darker is longer".

**Header.** A book icon top right opens the entries list. The card under the legend, "All journal entries · N entries", opens the same list.

**Day sheet.** Bottom sheet over the calendar, 720 pt tall, scrolls inside. Tap any cell with a row or any quest activity to open it. Empty days open nothing.

- Header: weekday in script blue, date large, and two tags right-aligned: `+N coins` and the day type.
- `Routines` section, then `Quests` section. Each has a title row with `done / total` in script blue and a chevron; tapping the row toggles the section. Routines default open, Quests default closed, both remembered per session. Cards use the Today page styles: routine cards on the warm grey, quest cards on their difficulty colour, light-version tag where it applied, check mark on the right.
- `THAT NIGHT` label with time written and word count, then the dark card: first three lines of the entry's text, prompts rendered as their answers only, then "Read the whole entry". The whole card is the tap target and opens the reader.
- No row that day: the dark card is replaced by a flat outline card, "Nothing written", with a `Write about this day` link that opens the editor on that date.

**Reader.** Full screen. Back, Share and Edit in the header. Date line, three tags (`N words`, `N quests done`, day type), then the blocks rendered the same way as the editor but read-only. `Edit` opens the editor on that date. Previous and next day buttons float at the bottom and skip days without a row.

**Entries list.** Reached from the Calendar header and from Trends. Newest first, grouped by month. One row per entry: day number and weekday on the left, two-line preview, word count, and a purple `N prompts` tag when the entry has any prompt blocks. A dark card at the top shows today's draft when one exists. Search filters on text, answers and questions.

## Trends tab

Trends is the fifth tab, between Calendar and Rewards. It shows patterns over a period; Calendar shows single days.

Period control at the top: `Weeks`, `Months`, `Year`, default Months. A floating bar at the bottom pages through periods. Everything below recomputes for the selected period.

Unlock rule: the tab shows its locked state until the user has rows on 7 distinct days, ever. Locked state is a dark card, `N of 7 nights written`, seven day tiles filled left to right, a `Write tonight's entry` button, and a list of what the tab will show. No charts render while locked.

| Module | Computation | Notes |
| --- | --- | --- |
| Three stat tiles | Total words in period; current writing streak in days; modal hour of `createdAt` | Streak counts consecutive local dates with a row, today included if written |
| Words per day | Bar per day, `wordCount`; 0 drawn as a 3 pt stub | Bars over 90th percentile in ink, rest in blue |
| What this month was about | Top 5 terms by TF-IDF, this period as the document, all other periods as the corpus | Tokenize with `NLTokenizer` (word unit), lowercase, drop stop words and tokens under 3 characters, keep bigrams that appear 3+ times. Horizontal bars, count on the right |
| Writing calendar | One cell per day in period, fill by word-count tier | Same tiers as the calendar glyph |
| Favorite quests | Top 3 by completion count, tie-break by mean rating from the Ratings feature | Show count and light-version count |
| Low energy days vs quests done | Bar per day, height = quest points earned, colour by day type | Footer line: mean points on low days as a percentage of mean on normal days |
| Grateful for, most often | Terms from answers to the `Grateful for` fixed prompt only, top 7 by count | Chip size by count, three sizes |
| Year at a glance | Twelve dots, size and fill by entries per month | Always the calendar year regardless of period control |

Computation runs on device. Cache per period and invalidate when any entry in that period is saved. TF-IDF needs at least 2 periods with rows; before that, show plain term frequency with the same filters and label it `most used words`.

The Ratings card currently on Calendar moves here, below Favorite quests.

## Edge cases and build order

Edge cases:

- Existing guided entries from the current build migrate to one `JournalEntry` with three `Prompt` blocks, `source = fixed`, answers carried over, empty answers kept. Existing free-text entries become one `Text` block.
- Two devices editing the same day: last write wins on the whole `blocks` array. Do not merge at block level in v1.
- Timezone change mid-day: the row keeps the date it was created under.
- The `Save to Journal` Shortcut keeps working. Export the entry as plain text, questions as a line in bold, answers under them.
- Trends and the entries list exclude the in-memory entry that has no row yet.

Build order, each step shippable on its own:

1. Data model and migration. Editor opens today's entry, autosaves, Done never locks. Delete the mode picker.
2. Prompt bar with the fixed chips and insertion rules. No LLM yet.
3. Calendar glyph, day sheet with the two collapsible sections and the That night card, reader.
4. Entries list and search.
5. `Ask me something` with the fallback to a fixed prompt.
6. Trends tab with the locked state and the three stat tiles. Add modules one at a time, words per day and favorite quests first, TF-IDF last.
