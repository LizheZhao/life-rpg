---
name: verify
description: Drive the LifeRPG iOS app (SwiftUI, five tabs behind a floating tab bar) on a dedicated iOS Simulator to prove a change works in the real app — launch, tap through a feature, and check the SwiftData store. Use after any change under LifeRPG/ (views, RootView, HealthService, import/export). Rules in LifeRPGCore are proven by `swift test`, not here.
---

# Verify LifeRPG on the simulator

This proves the **app layer**: views render the right thing, taps reach the right Core call, and what Core writes is what the screen shows. A rule (scoring, ladders, settlement) belongs to `swift test --package-path LifeRPGCore`; don't re-prove it through the UI.

Everything runs through `.claude/skills/verify/scripts/verify.sh` (below: `V`). Paths are relative to the repo root.

## Hard rules

- **Use only this checkout's own simulator** (`V udid`; named `LifeRPG-Verify-<hash of the checkout path>`), never another booted device. The user's other simulators may hold data they care about, the real phone is out of reach, and a simulator named plain `LifeRPG-Verify` belongs to whichever other checkout or session still uses the old script. `V up` creates and owns this one; the main repo and each git worktree get a separate simulator, store and build folder, because two sessions on one simulator reinstall the app and reset each other's store mid-run (observed). If `V doctor` shows row counts or a journal entry you did not make, or the app's process was started from another build folder, another session is driving this simulator: stop, and don't clean its instance.
- The simulator control tool asks the user to approve each new device the first time it is used; a `V up` that creates a new simulator therefore needs that approval before any tap. Without it only `V` and `xcrun simctl io … screenshot` work.
- **Never write to the store** with `sqlite3`. The app holds it open (WAL). Read only (`V sql`).
- No Health or Calendar permission sheet appears unless a button asks for one (Debug → *Allow Health access*, Settings → Workout detection → *Allow Calendar access*). The simulator has no health data, so a fresh day is `tier normal`, readiness `75`, energy `1.000`, and HRV/Sleep/Resting HR show `—`. A test of a *bad night* or a cycle day can't be driven here; that is a device check (`doc/DEV_PLAN.md`).
- Don't `rm -rf` anything; the project denies it.

## Launch

```bash
.claude/skills/verify/scripts/verify.sh up            # create sim if missing, boot, build, install, launch (~20s warm)
.claude/skills/verify/scripts/verify.sh up --fresh    # same, but wipes the app's data first (new seed, new grant, new day)
```

Ready when it prints `ready: <udid>` and `V doctor` shows `build: up to date` and a non-empty `rows:` line. Build output goes to `build/verify-derived/` (gitignored).

Pass the UDID from `V udid` as `device` to every `mcp__Claude_Code_iOS_Simulator__control` call.

## Doctor

```bash
.claude/skills/verify/scripts/verify.sh doctor
```

Read-only. Shows sim state, whether the built app is **stale** relative to `LifeRPG/` and `LifeRPGCore/Sources` (rebuild with `V up` if so), whether the app is running, the time-travel offset (read from the app's preferences file), row counts, the app's current day (host clock, the 05:00 rule and the offset) and, separately, the latest generated day. Run it first, and again whenever a screen disagrees with what you expect.

## Drive

There are no `accessibilityIdentifier`s and no UI-test target (adding one means editing `project.pbxproj`, which the repo forbids), and nothing here can read the accessibility tree. So drive by **visible label + screenshot**:

1. `control` action `screenshot` (device = the UDID). The image is 1320×2868 px; the control tool takes **points** = px ÷ 3. A screenshot shown at 921 px wide: points = shown px ÷ 2.093.
2. Locate the control by its text, convert to points, `control` action `tap`.
3. Screenshot again. Never chain taps blind, except the timed sequences a feature file spells out (the payout card's rating window is 8 s, shorter than a screenshot round trip).

Stable points on iPhone 17 Pro Max (440×956 pt):

| Target | x, y |
| --- | --- |
| Floating tab bar: Today / Calendar / Trends / Rewards / Settings | y = 880; x = 100 / 160 / 220 / 280 / 340 |
| Today header: `+` (Add for today) top-right; avatar top-left opens the Levels sheet | 396, 92; 44, 92 |
| Pushed page back button (Library, Debug, Design) | 40, 84 |
| Sheet `Done` (a pushed page's sheet, e.g. the Levels sheet) | 220, 890 |
| Close a bottom sheet with no button (the Calendar day sheet) | swipe down from about 220, 300 to 220, 900 |

Settings is the fifth tab. It lists Library, Workout detection, Output records to JSON, Tables (CSV), Restore from JSON…, a Journal section (Apple Journal status, the `Send my writing with the question request` toggle, the Shortcut set-up text), Design gallery and Debug; Library, Workout detection, Design and Debug are pushed onto the Settings stack, so the floating bar stays visible on them. At the default text size, with Settings scrolled to the top, the rows sit at about y = 247 (Library), 381 (Workout detection), 514 / 588 / 662 (the three Data rows), 795 (Design gallery); Debug is behind the floating bar there; scrolled to the bottom Design gallery sits at about 590 and Debug at 723. The Settings tab keeps whatever page was pushed when you switch tabs and come back (a relaunch resets it), so check which page you are on. The bar hides while the keyboard is up, and a tap issued right after an alert, sheet, card or file panel closes is swallowed.

Everything else moves with content: find it from a screenshot. Time travel is scripted rather than tapped: `V day <N>`.

Text entry: tap the field, then `control` action `text`. The tool returns before every character has landed, so wait a second (or screenshot) before tapping a button that depends on the text.

### Scripted handles

| Command | Does |
| --- | --- |
| `V day <N>` | Sets `debugDayOffset` to the absolute value N (simulator-only time travel) and relaunches; `V day 2` is two days ahead, `V day 0` returns to the real date. Same effect as Settings → Debug → Advance one day, and it works after that button too. Prints `offset=N; latest generated day <date>` |
| `V ledger` | Every ledger row and the balance (sum). The coin count on Today's level card must equal this |
| `V sql "<query>"` | Read-only SQL. Tables: `ZLEDGERENTRY`, `ZDAILYQUEST`, `ZROUTINEOCCURRENCE`, `ZDAILYCONTEXT`, `ZQUESTRATING`, `ZQUESTCOMMENT`, `ZREWARD`, `ZJOURNALENTRY`, `ZQUESTTEMPLATE`, `ZROUTINETASK`. Enums are `Z…RAW` strings; a rating is `-2…+2` in `ZRATING` |
| `V relaunch` | Terminate + launch; re-runs the foreground refresh (`ensureToday`, re-plan check) |
| `xcrun simctl privacy $(V udid) grant calendar com.lizhezhao.LifeRPG` | Grants calendar access without the system sheet (then `V relaunch`); `grant`/`revoke`/`reset` also exist for photos, contacts and others. There is no Health equivalent |

## Evidence

A proof is: the **action** (screenshot before + after, or the dialog), the **resulting screen**, and a **read-only second view** from the store. Goal for every mutation: what the screen shows equals what `V sql` / `V ledger` returns.

- Exercise the real tap path. Don't insert rows with SQL, and don't use Debug → *Reopen today* to set up a state you then claim the app produced.
- Capture with `V shot <feature-id>-<step>` (writes `build/verify-evidence/<name>.png`) and save query output with `V ledger | tee build/verify-evidence/<feature-id>-ledger.txt`.
- Completion is final and each reveal is rolled once; don't expect to repeat a completion on the same quest. For a second pass use `V up --fresh`, or Debug → **Reopen today** (marks today undone and removes the ledger entries that paid for it).
- Report a path you couldn't reach with the command and the unmet precondition. Don't report a skipped entry point as verified through another.

## Gotchas

- **The app's day ends at 05:00.** Between 00:00 and 05:00 host time, the app's "today" is *yesterday's* date. `V doctor` prints both. Don't read a day-key mismatch as a bug before checking the clock.
- On a freshly booted simulator the first day generation can take 10s+, and Today briefly shows `0 random slots` / "No quests today — the pool is empty". That is not an empty pool: `V up` waits until quests exist (60s cap); if you launch by hand, run `V doctor` until `dailyQuest` is above 0 before judging the screen.
- The control tool's `screenshot` can show a frame several seconds old, and its taps do not flip SwiftUI `Toggle` switches (buttons, steppers, pills and segmented controls are fine): five taps on Rewards' `Saving for this` and one on Library's `On` changed nothing. Verify every tap's effect with `V shot` or `V sql`, and treat a switch as unreachable by tap.
- A tap issued right after a sheet or alert dismisses is swallowed. Screenshot first and re-tap.
- Time travel writes future-dated rows that never go away (going back doesn't undo). It is simulator-only on purpose. After a time-travel proof, `V up --fresh` to start clean.
- Completing a quest or routine opens one centered card (disc and title, a `?` box for quests or a `+N` pill for routines, a full-width `Complete` pill, a quiet `Not yet`), not an alert or inline toggle. After `Complete` the same card rolls, lands on `+N`, then asks `how did that feel?` (five thumbs → ratings −2…+2, then `Done`). It closes by itself 8 s after the rate phase appears or the last pick, and the rating is written only if one was picked: a screenshot read between `Complete` and the thumb is slower than that. Feature files give the blind sequence.
- System file panels remember what is already there. A second export on the same day collides with `LifeRPG-<day>.json` (`Replace Existing Item`: choose `Keep Both`), and the restore picker opens on Browse → On My iPhone, not Recents.
- Time travel works through the app's container preferences: `V day` writes them with the app stopped and restarts the simulator's `cfprefsd`. Don't set the offset with `simctl spawn … defaults write`; once the app has written the key itself (any tap on Advance one day) that value is ignored.
- HealthKit and EventKit auto-verify can't be exercised: no data and no calendar on a fresh sim. Debug → *Allow Health access* shows the real system sheet; don't confuse a dismissed sheet with an app failure.
- Fixed day keys in a feature recipe will go stale. Read today's from `V doctor` (`app day`).

## Cleanup

```bash
.claude/skills/verify/scripts/verify.sh down      # terminate the app; shut the sim down if `up` booted it
.claude/skills/verify/scripts/verify.sh destroy   # also delete the LifeRPG-Verify sim (rarely needed)
```

Neither removes `build/verify-evidence/` or `build/verify-derived/`. Proof artifacts survive teardown; delete them yourself only when asked.

## Feature map

Read [`features/README.md`](features/README.md) before driving: it has the baseline state and one recipe per user-facing feature. A proof that drives one convenient entry point is incomplete when the map lists others. Keep it honest with `/maintain-verification-skill`.
