# Reminders

Settings → Reminders holds two local notifications, both off until switched on: an evening one (20:00, `Write about today`) and a morning one (`Today`, naming how many routines are due). Switching one on asks for notification permission. The queue is planned again whenever the app comes forward, goes to the background or a setting changes, so writing today's entry and leaving removes tonight's reminder.

## Sub-features

- `rem-switches` two switches, `Evening: write about today` (`At 20:00, unless you have already written`) and `Morning: what is due today` (`Says how many routines are due; the quests are drawn when you open the app`), both off on a fresh install; a stepper `Morning at 8:00` (5 to 11) appears while the morning switch is on; the footer says `Reminders are local: nothing leaves your phone. Writing and then leaving the app cancels tonight's.`
- `rem-permission` switching one on shows the system prompt `“LifeRPG” Would Like to Send You Notifications` the first time; a refusal puts the switch back off and shows `LifeRPG isn't allowed to send notifications. You can change that in iOS Settings.` with `Open iOS Settings`.
- `rem-queue` Debug → `Reminders` lists what is queued, soonest first (`journal-<day> · <date> at 8:00 PM`, `morning-<day> · …`), with `Rebuild the queue` and `Test in 5 s`. Fourteen days from today: a morning and an evening reminder each, minus anything already past (after 08:00 today's morning one is not queued) and minus tonight's when today already has writing. At most 28 requests.
- `rem-cancel` write something in today's journal, leave the app (Home) and come back: `journal-<today>` is gone from the queue, tomorrow's stays.
- `rem-copy` evening: `Write about today` / `A few lines is enough. Pull in a question if you want one.` Morning: `Today` / `N routines are due today. Open the app to see today's quests.` (`1 routine is due today…` for one, `Open the app to see what today asks.` for none). It never says the quests are ready.

## How to get to it (user POV)

- Settings tab → Reminders (third section, under Auto-verify). Debug (bottom of Settings) → Reminders.

## Driving it with the simulator

Preconditions: `V up --fresh`. `simctl privacy` cannot grant notifications, so permission is given through the real prompt.

- **Permission (driven).** Settings → Debug → scroll to `Reminders` (it sits between `Testing` and `Time travel`; about two screens down from the top of Debug, but the page keeps its scroll position, so read the live screen with `V shot`). Tap `Test in 5 s` (about 280, 658 pt there): the system prompt appears; tap `Allow` (about 294, 560 pt). The queue then lists `debug-test · <time>` and the note `A test reminder fires in 5 seconds`. The reminder fires while the app is in front, where iOS shows nothing: to see a banner, press Home within five seconds (not driven).
- **Switches (not reachable by tap).** The control tool cannot flip a `Toggle`, so set the state through the app's defaults and relaunch: `xcrun simctl terminate $(V udid) com.lizhezhao.LifeRPG`, then `xcrun simctl spawn $(V udid) defaults write com.lizhezhao.LifeRPG notify.journal -bool true` and the same for `notify.morning`, then `xcrun simctl launch …`. Settings then shows both switches on and the `Morning at 8:00` stepper. The stepper itself is a normal control (`+` / `−`).
- **Queue (driven).** With both on and permission given, Debug → Reminders (the launch already rebuilt the queue; `Rebuild the queue` does it again). At 08:22 the queue held `journal-<today> … 8:00 PM`, then `morning-` and `journal-` for each of the next days up to day 14, and no morning reminder for today.
- **Cancel by writing (driven).** Today → book button (about 342, 92 pt), type a few words (a row appears: `V sql "select ZDAYKEY, substr(ZBLOCKSJSON,1,60) from ZJOURNALENTRY"`), press Home (`control` button `HOME`), relaunch (`xcrun simctl launch`), reopen Debug → Reminders: the queue now starts at tomorrow's `morning-`, `journal-<today>` is gone.

## Gotchas

- `simctl spawn … defaults write` writes a device-level preference that survives uninstalling the app: the two switches stayed on after `V up --fresh`. To switch them off again write `-bool false`.
- Reminders use the real clock. `V day N` does not move them, and the queue is planned from the real now, so after a day offset the Debug list shows real dates.
- The control tool's own screenshots lag by a frame or more; this page was driven reading `V shot`. Taps are in points: a displayed y in the 921-px screenshot divided by 2.093.
- Debug's page scroll position survives leaving and re-entering it; after re-entering, scroll back up before looking for a section.
- Whether a reminder is delivered, how it looks on the lock screen, the denied path and survival across a restart are not verified here; they need a device.
