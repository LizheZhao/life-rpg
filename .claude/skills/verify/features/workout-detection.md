# Workout detection

Settings → Workout detection is where the user lets the app read calendars and says which event titles count as workouts, so a workout event auto-completes the matching routine or quest. The page shows the calendar permission, which calendars to read, the title keywords, a button to check now and a card with the result of the last check.

## Sub-features

- `wd-access` `Calendar access` shows its state (`Not asked yet`, `Allowed`, `Write only`, `Denied`); without full access a button reads `Allow Calendar access` (not asked yet) or `Open iOS Settings`.
- `wd-calendars` with full access: a `Calendars` section with an `All calendars` toggle (off by default) and a multi-select list of the device's calendars (title and source, a check for selected); the footer is `Only the checked calendars are read.` while the toggle is off.
- `wd-keywords` the `Title keywords, comma separated` field; it saves on Return, on keyboard dismiss, on leaving the page and on backgrounding, not on every keystroke; with no keywords nothing is detected.
- `wd-check` `Check for workouts now` ends editing and re-reads (it also runs on every foreground); it shows a spinner.
- `wd-last` the `Last check` card: a title (`Verified just now`, `Nothing new verified` or `Nothing detected`), `Checked <time>`, the verified titles, a reason line, then `Calendar events read` (`N since <day>`), `Matched a keyword`, `Workouts today`, `Mindful today`, and a `Did not match` list (up to three, all-day ones tagged) when events were rejected.

## How to get to it (user POV)

- Settings tab → Workout detection (the only row of the `Auto-verify` section, second after `Library`); back with the round button top-left (about 42, 92 pt).

## Driving it with the simulator

Preconditions: `V up --fresh`.

- **Open the page.** Tap the Settings tab (x=340, y=880), then `Workout detection` (about 220, 381 pt at the top of Settings). On a fresh simulator: `Calendar access — Not asked yet`, `Allow Calendar access`, `Keywords`, `Check for workouts now`, `Last check` reading `Nothing detected`, `Checked <time>`, `Calendar access is off, so no events could be read. Allow it under Access.`, `0 since <day>`, `0`, `None`, `0 min`.
- **Grant the permission without a sheet (driven).** `xcrun simctl privacy $(V udid) grant calendar com.lizhezhao.LifeRPG`, then `V relaunch` and reopen the page: `Calendar access — Allowed`, and `Calendars` lists the simulator's `Calendar` (Default), `Birthdays` (Other) and `US Holidays` (Subscribed Calendars) with `All calendars` off. With nothing selected the last check says `No calendar is selected. Turn on All calendars or check at least one.`; with no keywords `No keywords are set. An event only counts when its title contains one.`; with events but no match `Events were found, but none has a keyword in its title or sits in a selected calendar.` (the reason lines are from source; only the access states were driven).
- **A detected workout (not reached).** It needs a calendar event on the app's day that is in a selected calendar, has a keyword in its title, is not all-day, ends before now, and is long enough for an open item (the seed has `calendar_workout:20/25/40` routines in `doc/routine_quests.csv` and quests in `doc/side_quests.csv`). Creating the event is the unproven part: `simctl` has no calendar-add command, and opening an `.ics` with `xcrun simctl openurl` raises a Files "Save as" panel (it previews the event, then offers to save the file; it does not import it), so that route does not work. Untried: adding the event by driving the simulator's Calendar app (`com.apple.mobilecal`). Report it `verified-unreachable` until that is shown; the matching rules are proven by `AutoVerifyTests` in Core.

## Gotchas

- `Allow Calendar access` (when not granted by `simctl privacy`) raises the real iOS permission sheet. Answering it is a state change on the verify sim only; don't confuse a dismissed sheet with an app failure.
- The Debug page's sensor report shows `Health read failed: …` with the system's own wording on a simulator with no Health data, and the app's lines `Today: N mindful min, workouts none` and `Workout filter not set — calendar auto-verify is off`.
- The keyword field is committed on Return or dismissal: typing alone is not enough, and `Check for workouts now` ends editing first.
- After the `.ics` attempt a status-bar link `◂ Files` appears and the Files panel stays on top until dismissed (swipe down from the top); bring the app back with `xcrun simctl launch`.
