# Export and restore JSON

Settings → Data offers `History (JSON)`, `Ratings & comments (CSV)` and `Restore from JSON…`. Export writes the user's history out through the system file exporter; restore reads a JSON file, shows a summary (days covered, row counts, balance after) and asks before replacing history.

## Sub-features

- `exp-json` export history as JSON.
- `exp-csv` export ratings and comments as CSV.
- `exp-restore` pick a JSON, see the summary, confirm `Replace`; balance and total earned equal the source's.

## How to get to it (user POV)

- Settings tab → Data section.

## Driving it with the simulator

Preconditions: `V up --fresh`, then complete one quest so there is history to carry.

- **Open Settings.** Tap the Settings tab (x=309, y=880). The Data rows are at about y = 348 (`History (JSON)`), 400 (`Ratings & comments (CSV)`), 452 (`Restore from JSON…`).
- **Export (driven).** Tap `History (JSON)`; wait 5 s, the system file exporter opens (the first presentation is blank for a moment) with the name `LifeRPG-<day>`. Tap `Save` (about 384, 104) to write it into On My iPhone. The file lands in the simulator's `File Provider Storage` folder and shows under Recents in the restore picker. `Ratings & comments (CSV)` opens the same panel for a folder named `LifeRPG-feedback-<day>`; swipe down from the panel's top edge to dismiss without saving.
- **Restore (driven).** Complete one quest after exporting so the balance differs, then tap `Restore from JSON…`; the file picker opens on Recents. Tap the file: the `Replace all history?` alert lists the counts and `Balance after restoring`. Tap `Replace`; `V ledger` returns the exported balance and the Today tab shows the quest open again. A tab tap right after the alert closes is swallowed; tap again.

## Gotchas

- These are system panels (document picker). They are driven by screenshot like everything else, but the file locations are not stable handles; expect to spend a step finding the saved file.
- Restore is destructive: it replaces every history table. Only restore on the verify sim.
- The round-trip numbers (balance, total earned) are proven by `JSONImportTests` in Core; this recipe proves only that the panels and the confirmation appear and the app ends in the same state. Driven once on the verify sim, with the balance 100 → 107 → 100 round trip.
