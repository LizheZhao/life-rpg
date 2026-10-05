# Export and restore JSON

Settings → Data offers `Output records to JSON`, `Tables (CSV)` and `Restore from JSON…`. Export writes the user's history out through the system file exporter; restore reads a JSON file, shows a centered card with a summary (backup date, days covered, row counts, balance after) and asks before replacing history. The backup (schema version 8, restore reads 3–8) carries the journal entries too.

## Sub-features

- `exp-json` export history as JSON (`LifeRPG-<day>.json`, `schemaVersion` 8).
- `exp-csv` export tables as a CSV folder (`LifeRPG-tables-<day>`) holding `history-<day>.csv`, `ratings-<day>.csv` and `comments-<day>.csv`.
- `exp-restore` pick a JSON, see the card `Replace all history?`, confirm `Replace everything`; balance, ratings, routines and journal entries equal the source's. `Not yet` or a tap on the dim leaves the store alone.
- `exp-reinstall` the acceptance round trip: export, reinstall (`V up --fresh`), restore. The exported file sits in the simulator's Files, which an app uninstall does not touch.
- `exp-error` a refused file shows a banner in the Data section prefixed `Import failed: ` (from the source, not driven: `This file isn't a Life RPG export.`, `Exported by a newer build (schema N). Update the app first.`, `This export predates import. Export again with this build.`, `Import cancelled, nothing changed: …` when the audit finds a problem and rolls back); a failed export shows `Export failed: …`.

## How to get to it (user POV)

- Settings tab → Data section (the Journal section below it has no export or restore rows).

## Driving it with the simulator

Preconditions: `V up --fresh`, then complete one quest so there is history to carry, and write a journal entry ([journal-editor](./journal-editor.md)). Note the balance B1, the ledger and rating counts, and `V sql "select count(*) from ZJOURNALENTRY"` (E1).

- **Open Settings.** Tap the Settings tab (x=340, y=880). At the top of Settings the rows are at about y = 247 (`Library`), 381 (`Workout detection`), 514 (`Output records to JSON`), 588 (`Tables (CSV)`), 662 (`Restore from JSON…`); the Journal section (`Apple Journal`, the `Send my writing with the question request` toggle, the Shortcut set-up text), `Design gallery` and `Debug` follow below.
- **Export.** Tap `Output records to JSON`; wait 5 s, the system file exporter opens on `On My iPhone` with `Save as LifeRPG-<day>`. Tap `Save` (about 385, 104). If a file of that name is already there (earlier runs leave `LifeRPG-<day>.json` in the simulator's Files), `Replace Existing Item` appears: choose `Keep Both` (about 220, 558) — the new file is `LifeRPG-<day> 2.json` — rather than overwrite a snapshot someone else made.
- **Change the state (same install).** Spend or earn something so the balance differs from B1 (for example redeem a reward, see [rewards](./rewards.md)).
- **Restore.** Tap `Restore from JSON…`; the picker opens on Browse → On My iPhone (the last location used), not Recents. Tap the file you saved (check the time and size shown under its name; the 52-entry backup was 172 KB). A centered card appears: `Replace all history?`, `Backup exported <date> at <time>, covering <first> – <last>.`, a counts line (`170 quests, 110 routines, 1 ledger entries, 60 ratings, 0 comments, 0 rewards.`, which has **no journal count**), `Balance after restoring: <B1>.`, `Everything in this app's history is replaced by the backup.`, `Replace everything` and `Not yet`; the floating tab bar is hidden. Tap `Replace everything` (about 220, 563). `V ledger` returns B1, the other counts match the card, and `select count(*) from ZJOURNALENTRY` returns E1.
- **Reinstall round trip (driven).** After the export, `V up --fresh`: `V sql` shows 0 journal entries, 0 ratings and the 100-coin grant. Restore the file as above: 52 journal entries, 60 ratings, 110 routine occurrences, 170 quests and balance 100 come back, and the entry written by hand is `done` with its 4 blocks intact.
- **CSV.** Tap `Tables (CSV)`; the same panel opens for a folder `LifeRPG-tables-<day>`. Swipe down from about y=150 to y=800 to dismiss without saving.

## Gotchas

- These are system panels (document picker). They are driven by screenshot like everything else, but the file locations are not stable handles; expect to spend a step finding the saved file.
- The confirmation is a card (`Replace everything` / `Not yet`), not an alert; builds before commit `1f6a520` showed an alert with `Replace` and `Cancel`. Read the buttons from a screenshot.
- Restore replaces the history tables (quests, routine occurrences, ledger, day settings, ratings, notes, rewards). A backup that carries `journalEntries` also replaces the journal entries; an older backup (before schema 8) leaves them alone and converts its old journal turns into entries. The quest and routine library is kept and re-linked by text. Only restore on the verify sim.
- A re-run leaves a new `LifeRPG-<day> N.json` in the simulator's Files each time, and `V up --fresh` does not remove them; that is residue of the run and is kept. Pick the right file by its time and size.
- The round-trip numbers are proven by `JSONImportTests` in Core; this recipe proves that the panels and the confirmation appear and the app ends in the same state.
- The simulator's Files and its other apps are shared with any other session driving the same simulator (see the README on one simulator per checkout).
