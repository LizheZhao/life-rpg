# Export and restore JSON

Settings → Data offers `Output records to JSON`, `Ratings & comments (CSV)` and `Restore from JSON…`. Export writes the user's history out through the system file exporter; restore reads a JSON file, shows a centered card with a summary (backup date, days covered, row counts, balance after) and asks before replacing history.

## Sub-features

- `exp-json` export history as JSON (`LifeRPG-<day>.json`).
- `exp-csv` export ratings and comments as a CSV folder (`LifeRPG-feedback-<day>`).
- `exp-restore` pick a JSON, see the card `Replace all history?`, confirm `Replace everything`; balance and total earned equal the source's. `Not yet` or a tap on the dim leaves the store alone.
- `exp-error` a refused file shows a banner in the Data section prefixed `Import failed: ` (from the source, not driven: `This file isn't a Life RPG export.`, `Exported by a newer build (schema N). Update the app first.`, `This export predates import. Export again with this build.`).

## How to get to it (user POV)

- Settings tab → Data section.

## Driving it with the simulator

Preconditions: `V up --fresh`, then complete one quest so there is history to carry. Note the balance B1 from `V ledger`.

- **Open Settings.** Tap the Settings tab (x=309, y=880). At the top of Settings the rows are at about y = 381 (`Workout detection`), 514 (`Output records to JSON`), 588 (`Ratings & comments (CSV)`), 662 (`Restore from JSON…`), 795 (`Design gallery`); Debug sits behind the floating bar until you scroll.
- **Export.** Tap `Output records to JSON`; wait 5 s, the system file exporter opens on `On My iPhone` with `Save as LifeRPG-<day>`. Tap `Save` (about 385, 104). If a file of that name is already there (earlier runs leave `LifeRPG-<day>.json` in the simulator's Files), `Replace Existing Item` appears: choose `Keep Both` (about 220, 558) — the new file is `LifeRPG-<day> 2.json` — rather than overwrite a snapshot someone else made.
- **Change the state.** Spend or earn something so the balance differs from B1 (for example redeem a reward, see [rewards](./rewards.md)).
- **Restore.** Tap `Restore from JSON…`; the picker opens on Browse → On My iPhone (the last location used), not Recents. Tap the file you saved (check the time and size shown under its name). A centered card appears: `Replace all history?`, `Backup exported <date> at <time>, covering <first> – <last>.`, a counts line (`8 quests, 11 routines, 20 ledger entries, 3 ratings, 2 comments, 1 rewards.`), `Balance after restoring: <B1>.`, `Replace everything` and `Not yet`; the floating tab bar is hidden. Tap `Replace everything` (about 220, 563). `V ledger` returns B1 and the other counts match the card (`V sql "select count(*) from ZQUESTRATING"`).
- **CSV.** Tap `Ratings & comments (CSV)`; the same panel opens for a folder `LifeRPG-feedback-<day>`. Swipe down from about y=150 to y=800 to dismiss without saving.

## Gotchas

- These are system panels (document picker). They are driven by screenshot like everything else, but the file locations are not stable handles; expect to spend a step finding the saved file.
- The confirmation is a card (`Replace everything` / `Not yet`), not an alert; builds before commit `1f6a520` showed an alert with `Replace` and `Cancel`. Read the buttons from a screenshot.
- Restore is destructive: it replaces every history table (the quest and routine library is kept and re-linked by text). Only restore on the verify sim.
- A re-run leaves a new `LifeRPG-<day> N.json` in the simulator's Files each time; that is residue of the run and is kept.
- The round-trip numbers (balance, total earned) are proven by `JSONImportTests` in Core; this recipe proves that the panels and the confirmation appear and the app ends in the same state. Driven this pass: balance 21 → 1 → 21, ratings 3, comments 2.
