# Name and starting over

The first launch asks `What should we call you?` once; the answer is shown in Today's greeting and can be changed in Settings → You. Settings → Data → `Erase all records…` deletes the history and the journal, keeps the library, and starts again with the opening 100 coins.

## Sub-features

- `prof-ask` a sheet on first launch: `What should we call you?`, `Only used for the greeting. It stays on this phone.`, a `Your name` field (focused, words capitalised, no autocorrect), `Continue` (disabled until something is typed) and `Skip`. Asked once whatever the answer (`profile.asked`); swiping the sheet away counts as skipping.
- `prof-greeting` Today reads `Good morning, <name>,` (afternoon, evening by the clock); with no name it is `Good morning,`. The name is cleaned: whitespace collapsed, 30 characters.
- `prof-settings` Settings → `You` → `Your name` (the value, or `Not set`) opens the same sheet (`Your name`, `Used for the greeting on Today. It stays on this phone and isn't in a backup.`, `Not now`).
- `prof-erase` `Erase all records…` (trash icon, under `Restore from JSON…`) opens the centered card `Erase all records?`: `This erases N quest and routine records, N coin entries, N ratings and notes, N rewards, N journal entries. Your library stays, with your edits. This can't be undone: output records to JSON first if you may want them back.` with `Erase everything` and `Not yet`.
- `prof-after` after `Erase everything` the history tables are empty except the new opening grant (`grant | 100 | Starting balance`), today is drawn again, the library keeps its rows and edits, and the name stays.

## How to get to it (user POV)

- First launch (or `V up --fresh`): the sheet appears by itself. Settings tab → top section `You`. Settings → scroll to `Data` → `Erase all records…`.

## Driving it with the simulator

Preconditions: `V up --fresh`. The name is in `UserDefaults` (`profile.name`, `profile.asked`).

- **First launch (driven).** About six seconds after `V up --fresh` the sheet is up with the keyboard open (`V shot`). Type a name (the control tool types into the focused field), tap `Continue` (about 220, 519 pt with the keyboard up). Today's greeting shows it. Note: typing two spaces in a row makes iOS insert a period (smart punctuation); an earlier run typed `  Ryo   Zhao  ` and got `Ryo. Zhao.`, which is the keyboard, not the cleaning (autocorrection is now off for the field but that shortcut is a keyboard setting).
- **Settings (driven).** Settings tab: `You` / `Your name` / the name at the top.
- **Erase (driven).** Make some history first (a journal entry through the book button is enough; `V sql "select (select count(*) from ZJOURNALENTRY), (select count(*) from ZLEDGERENTRY), (select count(*) from ZDAILYQUEST), (select count(*) from ZQUESTTEMPLATE), (select count(*) from ZROUTINETASK)"`). Settings → scroll one screen → `Erase all records…` (about 220, 585 pt after one swipe from 760 to 300): the card lists the counts (`4 quest and routine records, 1 coin entry, 1 journal entry`). `Not yet` (about 220, 577 pt) changes nothing. Open it again and tap `Erase everything` (about 220, 523 pt): journal 0, ledger one `grant | 100`, `ZDAILYQUEST` 4 (today drawn again), `ZDAILYCONTEXT` 1, library still 108 / 19, `ZLASTCOMPLETEDDAYKEY` null everywhere, and Today shows 100 coins and the same name.

## Gotchas

- The name and `profile.asked` are not in the store: `V up --fresh` uninstalls the app and asks again, but `simctl spawn … defaults write` writes a device-level plist that an uninstall does not clear (the reminder switches stayed on across a fresh install), so a leftover key can survive a fresh install.
- A backup does not carry the name; a restore onto a new phone asks again.
- Erase re-plans the reminder queue (`onImported`), so tonight's reminder comes back once today's entry is gone.
- Erase is not something to demonstrate on the author's own phone store: export first.
