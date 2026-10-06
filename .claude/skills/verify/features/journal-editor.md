# Journal editor

A full-screen page for one day's journal entry: free text blocks and prompt blocks (a purple question over an answer), a chip bar above the keyboard with fixed prompts and an `Ask me something` pill. It autosaves into `JournalEntry` (one row per day, `ZBLOCKSJSON` of blocks) and the entry's day is the app day, which ends at 05:00.

## Sub-features

- `je-open` the editor opens for today from the Today book button (`Journal`) or the dark journal card (`Start writing` / `Keep going · N words`), from the Calendar day sheet (`Write about this day`), from the entries page (`Tonight, in progress`), from the reader's pencil, and from Trends' `Write tonight's entry`.
- `je-type` typing writes a text block; the header label runs `Saving…` → `Saved just now` (about 10 s) → `Saved`, and the chip bar counts `N words`.
- `je-chip` the chips `Favorite moment`, `Grateful for`, `Low energy felt like`, `Tomorrow` insert a fixed prompt at the cursor; a used chip is dimmed and does nothing; the cursor lands in the new answer.
- `je-keys` Return at the end of an answer starts a new text block; Backspace in an empty answer removes the prompt; a long-press on a question offers `Remove question` (the answer stays as text).
- `je-ask` the `Ask me something` pill inserts a model question (`source: llm`) or, when the model is unavailable or fails, the first missing fixed prompt with a toast; five model prompts cap it (`Enough questions for one night`); writing that holds a safety word gets a safety card instead of a question.
- `je-done` `Done` closes and marks the entry done (`ZDONEAT` set); `Close` closes without marking; an entry with only whitespace is deleted.
- `je-hand-off` the Apple Journal hand-off sends a finished day once at 05:00 through the user's Shortcut. Device only; the Debug page has a simulator stand-in.

## How to get to it (user POV)

- Today tab → book button (about 342, 92 pt), or the dark journal card (20:00 to 05:00). Calendar → a day → `Write about this day →`.

## Driving it with the simulator

Preconditions: `V up --fresh`. Debug → `Journal model` says `available` on this simulator, so `Ask me something` calls the real on-device model unless you force a result.

- **Open.** Tap the book button (or Calendar → today's cell → `Write about this day`). The header reads `Close`, a save label (`Saved`), `Done`; the heading `Monday, October 5 · today` by day (`· tonight` from 20:00 to 05:00, no suffix for a past day); the cursor is in an empty page; the bar at the bottom reads `Ask me something`, `Favorite moment`, `0 words`. `V sql "select count(*) from ZJOURNALENTRY"` is 0: opening writes nothing.
- **Type.** Type `hello world today` and wait about 2 s. The label reads `Saved just now` and the bar `3 words`. `V sql "select ZDAYKEY, ZBLOCKSJSON, ZDONEAT is null from ZJOURNALENTRY"` returns one row for the app day, `[{"id":"…","text":"Hello world today","type":"text"}]` (the first letter is capitalised by the keyboard), draft `1`.
- **Chip.** Tap `Favorite moment` (about 285, 893 pt) and type `a quiet walk`. A purple question `What was your favorite moment today?` appears over the answer, the chip dims, the bar reads `6 words`. The JSON gains `{"answer":"A quiet walk","fixedKey":"favoriteMoment","question":"What was your favorite moment today?","source":"fixed","type":"prompt"}`.
- **Ask.** Tap `Ask me something` (about 107, 893 pt). With the model available a question tailored to the day appears at the cursor (observed: `What got in the way of your planned job applications today?`), stored with `"source":"llm"` and no `fixedKey`, and the cursor sits in its empty answer. The wording is the model's, so assert the block, not the text.
- **Safety.** Type a safety word in an answer (observed with `feeling hopeless`), **wait a second so the text has landed**, then tap the pill: a card `That sounds heavy. This is only a journaling tool and can't help the way a person can. If you might hurt yourself, please reach out to someone you trust or a local crisis line.` with `Got it` appears and nothing is inserted (block count unchanged). Tap `Got it` (about 52, 818 pt).
- **Done.** Tap `Done` (about 382, 92 pt). When opened from a Calendar sheet it returns to that sheet; `ZDONEAT` is now set (`select ZDONEAT is not null from ZJOURNALENTRY` is `1`), the sheet's night card reads `THAT NIGHT <time> · 8 words`, and Trends counts the day. Unanswered prompts persist (the reader shows `Not answered`).
- **Forced results (Debug, simulator only).** Settings → Debug → `Ask me something (simulator only)`: `Real`, `Question` (a canned question), `Timeout` (the pill spins about 6 s, then a fixed prompt and the toast `Couldn't reach the guide, here's a standard one`), `Error` and `Garbage` (the same, at once). The fixed fallback order is Favorite moment, Grateful for, Tomorrow, Low energy felt like; with all four present the toast reads `Couldn't reach the guide, and every standard question is already in your entry`. Not driven this pass.
- **Journal time (driven).** Debug → `Journal time (simulator only)` (about 173, 393 pt for `Evening`, 80 for `Real`): `Real / Evening / Daytime / Cleared`. `Evening` forces the clock to 21:00, `Daytime` and `Cleared` to 12:00 (`Cleared` also treats the day as cleared). It drives the Today card, the editor's date line, the entries page card title and the Trends button. Under `Evening`: Today shows the card (`tonight`, `Keep going · 2 words`), the editor reads `Monday, October 5 · tonight`, Trends reads `Write tonight's entry`. By day the same surfaces read `today` / `Today, in progress` / `Write today's entry`. Put it back on `Real` afterwards.

## Gotchas

- **The `text` tool returns before every character has landed.** A pill tap straight after typing sent the request without the new word and inserted a question instead of the safety card; the second tap (after the text had landed) showed the card. Wait a second between typing and any tap that reads the text.
- On a freshly installed simulator the first time the keyboard appears iOS shows a `Speed up your typing by sliding your finger across the letters` panel over the lower half of the screen with a `Continue` button (about 220, 907 pt); tap it before typing, or the first characters go nowhere.
- The editor is one `UITextView` per block: tap into the block, then type. It focuses the end of the last block on open.
- Return in free text inserts a plain newline; only Return at the very end of an answer makes a block. Save-time normalisation drops empty text blocks and joins adjacent text blocks with a newline; a prompt alone does not make an entry.
- Toasts fade after 4 s and the model can answer in a few seconds: screenshot quickly (`V shot`, not the control tool).
- Fixed chips do not count toward the cap of 5; only model prompts do.
- The Apple Journal Shortcut (`Get Journal Text to Send`, `Create Journal Entry`, the 05:00 Personal Automation) cannot run here; Debug → `Journal hand-off (simulator only)` → `Run Get Journal Text to Send now` calls the same hand-off at the shifted clock (the day must be written one day behind: `V day 1` first; a second press returns nothing). Real Apple Journal, Share sheet contents and the model's wording quality need a device.
- A Settings toggle `Send my writing with the question request` (default on) only changes the request text; it has no visible effect with a forced result.
- The `today` / `tonight` wording follows the hour only (the real clock, or the 21:00 / 12:00 that `Journal time` forces); time travel (`V day N`) moves the day key but never the hour, so it never changes the wording. The editor fixes its wording when it is built, so it does not flip mid-session.
