# Workout detection

Settings → Workout detection is where the user lets the app read a calendar and says which event titles count as workouts, so a workout event auto-completes the matching routine or quest. The page shows the calendar permission, the calendar choice, the title keywords, a button to check now and a card with the result of the last check.

## Sub-features

- `wd-access` `Calendar access` shows its state (`Not asked yet`) and `Allow Calendar access` asks the system for it.
- `wd-calendars` once access is granted, a list of calendars to pick one from.
- `wd-keywords` the `Title keywords, comma separated` field; with no keywords nothing is detected.
- `wd-check` `Check for workouts now` re-reads the calendar; it also runs on every foreground.
- `wd-last` the `Last check` card: result, time, events read, matched a keyword, workouts today, mindful minutes.

## How to get to it (user POV)

- Settings tab → Workout detection (second row, under Auto-verify); back with the round button top-left.

## Driving it with the simulator

Preconditions: `V up --fresh`.

- **Open the page.** Tap the Settings tab (x=309, y=880), then `Workout detection` (about 220, 381 pt at the top of Settings). The page lists `Access` (`Calendar access — Not asked yet`, `Allow Calendar access`), `Keywords` (a field with the hint `An event counts only if its title contains one of these keywords, so meetings do not count. All-day events never count. With no keywords, nothing is detected.`), `Check for workouts now` and `Last check`.
- **Read the last check.** On a fresh simulator the card reads `Nothing detected`, `Checked <time>`, `Calendar access is off, so no events could be read. Allow it under Access.`, then `Calendar events read 0 since <day>`, `Matched a keyword 0`, `Workouts today None`, `Mindful today 0 min`.
- **Not reachable here: a detected workout.** It needs a granted calendar permission (a system sheet from `Allow Calendar access`), a calendar holding an event whose title contains a keyword, and a routine or quest it can verify. A fresh simulator has no events and nothing in this skill can create one. Report it `verified-unreachable` with that prerequisite; the matching rules are proven by `AutoVerifyTests` in Core.

## Gotchas

- `Allow Calendar access` raises the real iOS permission sheet. Answering it is a state change on the verify sim only; don't confuse a dismissed sheet with an app failure.
- The Debug page's sensor report (`Authorization not determined`, `Workout filter not set — calendar auto-verify is off`) is the other place this state shows.
- The page was viewed and read in this pass; `Check for workouts now` and the keyword field were not exercised.
