# First-launch intro

A store with no history (no finished quest or routine, no written day) opens on a six-page full-screen intro before Today: the name, the quest tiers, what a finish pays, the journal, reminders, and Health and Calendar. Today's quests are drawn only after `Start my day`, so a Health connection made in the intro already shapes the day. The intro is not shown again once finished; Settings → You → `Show the intro again` replays it, and `Erase all records…` brings it back.

## Sub-features

- `onb-when` shown when `onboarding.done` is unset and `Onboarding.hasHistory` is false (Core-tested). A store with history (a restore, a phone in use) sets the flag instead and never shows it. `Erase all records…` clears the flag, and the intro opens at once (driven 2026-10-12, with the name filled in); unlike a first install, the erase has already drawn today again, so the day exists under the intro (`dailyQuest` 4 in `V sql` before `Start my day`).
- `onb-name` page 1: avatar, `hello, adventurer`, `What should we call you?`, a `Your name` field, `Continue` (disabled until something is typed) and `Skip` (`Not now` when a name exists). The keyboard closes when the page is left; a name typed and swiped past is still saved, but `Skip` / `Not now` drops what was typed and keeps the stored name.
- `onb-quests` page 2: `your day` / `Every morning, a fresh draw`; `Quests`: four tinted rows `Trivial` (headphones, `Add a song to a playlist`, `4`), `Easy` (heart, `Do a face mask`, `5–15`), `Medium` (speech bubble, `Ask someone a question`, `12–30`), `Hard` (map pin, `Day trip to a new town`, `25–50`); `Also on your page`: `Routines` (broom) and `One epic a week` (flag).
- `onb-loot` page 3: `loot` / `Every clear pays coins`; a quest card (`Compliment a stranger`, the reel landing on `+24` with `23` / `25` beside it, `quest · rolled 12–30`) and a routine card (`Do the laundry`, `+15`, `routine · fixed`); `Spend coins on rewards you set, or reroll a quest. Your day resets at 5 am.` The reel rolls each time the page comes into view; nothing is paid.
- `onb-journal` page 4: `dear diary` / `Write about your day`; a sample page with a general prompt and a quest-specific prompt in the editor's purple prompt style, a still `Ask me something` pill, `Save each day to Apple Journal`, `Trends unlock after 7 days of writing`.
- `onb-reminders` page 5: `daily login` / `Never miss a drop`; `Morning · 08:00` (`Today's quests are in. Come claim them.`) above `Evening · 20:00` (`Wrap up your day.`) — the times are the ones set in Settings → Reminders (08:00 and 20:00 by default; after `V pref notify.morningMinute integer 450` / `notify.eveningMinute integer 1260` the page read `07:30` / `21:00`, 2026-10-12) —, each its own switch (`NotificationService.set`: switching on asks iOS, a refusal leaves it off and shows `Open iOS Settings`); `Change the times any time in Settings.`
- `onb-connect` page 6: `power-ups` / `Let the day read you`; `Health` (`Slept badly? Lighter quests, bigger pay.`; on once the Health sheet has been answered) and `Calendar` (`Workouts on your calendar tick themselves off.`; a first grant sets the workout calendars to all); `Start my day`.
- `onb-skip` pages 2–4 have `Skip intro`, which jumps to page 5 (reminders are never skipped past silently).
- `onb-replay` Settings → You → `Show the intro again` opens it over Settings with the name filled in.

## How to get to it (user POV)

- A first install, or after `Erase all records…`. Settings tab → `You` → `Show the intro again`.

## Driving it with the simulator

Preconditions: `V up --fresh --intro` (plain `--fresh` marks the intro seen). It prints `ready (intro showing, …)`; `V doctor` shows `dailyQuest=0` until the intro is finished.

- **Walk through (driven 2026-10-09).** Name field about (220, 377); type, then `Continue` about (220, 527) with the keyboard up. `Next` is about (220, 840) and `Skip intro` about (220, 896) on every later page; page 6's button is `Start my day` at the same place. Capture each page with `V shot onb-<n>`. After `Start my day`: Today greets with the name, `V doctor` shows `dailyQuest` above 0, and the container plist (`plutil -p` on `$(xcrun simctl get_app_container $(V udid) com.lizhezhao.LifeRPG data)/Library/Preferences/com.lizhezhao.LifeRPG.plist`) holds `onboarding.done`, `profile.asked` and `profile.name`.
- **Not again (driven).** `V relaunch` opens on Today.
- **Replay (driven).** Settings tab, then `Show the intro again` at about (220, 321) with Settings at the top.

## Gotchas

- The switches on pages 5 and 6 can't be flipped by a tap of the control tool (a `Toggle`), so the permission paths are not driven; this simulator's device-level preferences hold `notify.journal` and `notify.morning` = 1 from an earlier session, so page 5's switches show on even on a fresh install (`xcrun simctl spawn $(V udid) defaults read com.lizhezhao.LifeRPG` shows them).
- The control tool's screenshot is too slow to catch page 3's reel rolling (1.6 s); only the landed `+24` has been seen.
- A tap right after the intro closes is swallowed; screenshot and tap again.
