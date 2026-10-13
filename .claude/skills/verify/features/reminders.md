# Reminders

Settings → Journal & reminders (one page since c1a782b, where Reminders and Journal used to be two) holds, in its `Evening` and `Morning` sections, two local notifications, both off until switched on, each with its own time: an evening one (20:00 by default, `Write about today`) and a morning one (08:00 by default, `Today`, naming how many routines are due). Switching one on asks for notification permission. The queue is planned again whenever the app comes forward, goes to the background or a setting changes, so writing today's entry and leaving removes tonight's reminder.

## Sub-features

- `rem-switches` two sections at the top of the page, `Evening` with the switch `Write about today` (no caption) and `Morning` with `What is due today` (caption `How many routines are due.`), both off on a fresh install; under each switch, while it is on, a `Time` row (an hour-and-minute picker: morning 05:00–11:59, evening 12:00–23:59, anything outside held to the edge). The long footer about local reminders is gone. The sections below on the same page are `Apple Journal` (the sent status line and one explanatory line), `Ask me something` (the `Send my writing with the question request` switch and its caption) and `Set up once` (the four Shortcut steps); see [journal-entries](./journal-entries.md) and [journal-editor](./journal-editor.md).
- `rem-permission` switching one on shows the system prompt `“LifeRPG” Would Like to Send You Notifications` the first time; a refusal puts the switch back off and shows `Notifications are off in iOS Settings.` (clay, in a section of its own under `Morning`) with `Open iOS Settings`.
- `rem-queue` Debug → `Reminders` lists what is queued, soonest first (`journal-<day> · <date> at <evening time>`, `morning-<day> · …`), with `Rebuild the queue` and `Test in 5 s`. Fourteen days from today: a morning and an evening reminder each, minus anything whose time today has already passed and minus tonight's when today already has writing. At most 28 requests.
- `rem-cancel` write something in today's journal, leave the app (Home) and come back: `journal-<today>` is gone from the queue, tomorrow's stays.
- `rem-copy` evening: `Write about today` / `A few lines is enough.` Morning: `Today` / `N routines due today.` (`1 routine due today.` for one, `Open the app to see what today asks.` for none). It never says the quests are ready.

## How to get to it (user POV)

- Settings tab → section `Journal & reminders` (under Auto-verify; one row of the same name opens the page). Debug (bottom of Settings) → Reminders. The intro's `daily login` page sets the same switches ([onboarding](./onboarding.md)).

## Driving it with the simulator

Preconditions: `V up --fresh`. `simctl privacy` cannot grant notifications, so permission is given through the real prompt.

- **Permission (driven).** Settings → Debug → scroll to `Reminders` (it sits between `Testing` and `Time travel`; about two screens down from the top of Debug, but the page keeps its scroll position, so read the live screen with `V shot`). Tap `Test in 5 s` (about 280, 658 pt there): the system prompt appears; tap `Allow` (about 294, 560 pt). The queue then lists `debug-test · <time>` and the note `A test reminder fires in 5 seconds`. The reminder fires while the app is in front, where iOS shows nothing: to see a banner, press Home within five seconds (not driven).
- **Switches and times (driven 2026-10-12 through `V pref`).** The control tool cannot flip a `Toggle` or turn a `DatePicker`, so write the preferences: `V pref notify.journal bool true`, `V pref notify.morning bool true`, and the times as minutes after midnight, `V pref notify.eveningMinute integer 1260`, `V pref notify.morningMinute integer 450` (each relaunches). Settings → Journal & reminders then shows both switches on with `Time` `9:00 PM` and `7:30 AM`, and the intro's `daily login` page reads `Morning · 07:30` / `Evening · 21:00`. An older build's `notify.morningHour` is still read when `notify.morningMinute` is absent.
- **Queue (driven).** With both on and permission given, Debug → Reminders (the launch already rebuilt the queue; `Rebuild the queue` does it again). At 08:22 the queue held `journal-<today> … 8:00 PM`, then `morning-` and `journal-` for each of the next days up to day 14, and no morning reminder for today.
- **Cancel by writing (driven).** Today → book button (about 342, 92 pt), type a few words (a row appears: `V sql "select ZDAYKEY, substr(ZBLOCKSJSON,1,60) from ZJOURNALENTRY"`), press Home (`control` button `HOME`), relaunch (`xcrun simctl launch`), reopen Debug → Reminders: the queue now starts at tomorrow's `morning-`, `journal-<today>` is gone.

## Gotchas

- Don't use `simctl spawn … defaults write`: it writes a device-level preference that survives uninstalling the app (the two switches stayed on after `V up --fresh` in an earlier pass). If a simulator still has that residue, clear it with `xcrun simctl spawn $(V udid) defaults delete com.lizhezhao.LifeRPG notify.journal` (and `notify.morning`). `V pref` writes the app's container plist, which `--fresh` removes.
- Reminders use the real clock. `V day N` does not move them, and the queue is planned from the real now, so after a day offset the Debug list shows real dates.
- The control tool's own screenshots lag by a frame or more; this page was driven reading `V shot`. Taps are in points: a displayed y in the 921-px screenshot divided by 2.093.
- Debug's page scroll position survives leaving and re-entering it; after re-entering, scroll back up before looking for a section.
- Whether a reminder is delivered, how it looks on the lock screen, the denied path and survival across a restart are not verified here; they need a device.
