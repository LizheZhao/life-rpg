---
name: verify
description: Drive the LifeRPG iOS app (SwiftUI, four tabs behind a floating tab bar) on a dedicated iOS Simulator to prove a change works in the real app — launch, tap through a feature, and check the SwiftData store. Use after any change under LifeRPG/ (views, RootView, HealthService, import/export). Rules in LifeRPGCore are proven by `swift test`, not here.
---

# Verify LifeRPG on the simulator

This proves the **app layer**: views render the right thing, taps reach the right Core call, and what Core writes is what the screen shows. A rule (scoring, ladders, settlement) belongs to `swift test --package-path LifeRPGCore`; don't re-prove it through the UI.

Everything runs through `.claude/skills/verify/scripts/verify.sh` (below: `V`). Paths are relative to the repo root.

## Hard rules

- **Use only the `LifeRPG-Verify` simulator**, never another booted device. The user's other simulators may hold data they care about, and the real phone is out of reach. `V up` creates and owns this one.
- **Never write to the store** with `sqlite3`. The app holds it open (WAL). Read only (`V sql`).
- No Health or Calendar sheet appears unless a Debug button asks for one. The simulator has no health data, so a fresh day is `tier normal`, readiness `75`, energy `1.000`, and HRV/Sleep/Resting HR show `—`. A test of a *bad night* or a cycle day can't be driven here; that is a device check (`doc/DEV_PLAN.md`).
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

Read-only. Shows sim state, whether the built app is **stale** relative to `LifeRPG/` and `LifeRPGCore/Sources` (rebuild with `V up` if so), whether the app is running, the time-travel offset, row counts, and the app's current day against the host clock. Run it first, and again whenever a screen disagrees with what you expect.

## Drive

There are no `accessibilityIdentifier`s and no UI-test target (adding one means editing `project.pbxproj`, which the repo forbids), and nothing here can read the accessibility tree. So drive by **visible label + screenshot**:

1. `control` action `screenshot` (device = the UDID). The image is 1320×2868 px; the control tool takes **points** = px ÷ 3. A screenshot shown at 921 px wide: points = shown px ÷ 2.093.
2. Locate the control by its text, convert to points, `control` action `tap`.
3. Screenshot again. Never chain taps blind.

Stable points on iPhone 17 Pro Max (440×956 pt):

| Target | x, y |
| --- | --- |
| Floating tab bar: Today / Calendar / Rewards / Settings | y = 880; x = 130 / 189 / 250 / 309 |
| Today header: `+` (Add for today) top-right; avatar top-left opens the Levels sheet | 396, 92; 44, 92 |
| Pushed page back button (Library, Debug, Design) | 40, 84 |
| Sheet `Done` button (day detail) | 383, 104 |

Settings is the fourth tab. It lists Library, History (JSON), Ratings & comments (CSV), Restore from JSON…, Design gallery and Debug; Library, Design and Debug are pushed onto the Settings stack, so the floating bar stays visible on them. At the default text size the rows sit at about y = 236 (Library), 348 / 400 / 452 (the three Data rows), 562 (Design gallery), 674 (Debug). The bar hides while the keyboard is up, and a tap issued right after an alert, sheet or file panel closes is swallowed.

Everything else moves with content: find it from a screenshot. Time travel is scripted rather than tapped: `V day <N>`.

Text entry: tap the field, then `control` action `text`.

### Scripted handles

| Command | Does |
| --- | --- |
| `V day <N>` | Sets `debugDayOffset` to N days (simulator-only time travel), relaunches. `V day 0` returns to the real date. Same effect as Settings → Debug → Advance one day |
| `V ledger` | Every ledger row and the balance (sum). The coin count on Today's level card must equal this |
| `V sql "<query>"` | Read-only SQL. Tables: `ZLEDGERENTRY`, `ZDAILYQUEST`, `ZROUTINEOCCURRENCE`, `ZDAILYCONTEXT`, `ZQUESTRATING`, `ZQUESTCOMMENT`, `ZREWARD`, `ZQUESTTEMPLATE`, `ZROUTINETASK`. Enums are `Z…RAW` strings; a rating is `-2…+2` in `ZRATING` |
| `V relaunch` | Terminate + launch; re-runs the foreground refresh (`ensureToday`, re-plan check) |

## Evidence

A proof is: the **action** (screenshot before + after, or the dialog), the **resulting screen**, and a **read-only second view** from the store. Goal for every mutation: what the screen shows equals what `V sql` / `V ledger` returns.

- Exercise the real tap path. Don't insert rows with SQL, and don't use Debug → *Reopen today* to set up a state you then claim the app produced.
- Capture with `V shot <feature-id>-<step>` (writes `build/verify-evidence/<name>.png`) and save query output with `V ledger | tee build/verify-evidence/<feature-id>-ledger.txt`.
- Completion is final and each reveal is rolled once; don't expect to repeat a completion on the same quest. For a second pass use `V up --fresh`, or Debug → **Reopen today** (marks today undone and removes the ledger entries that paid for it).
- Report a path you couldn't reach with the command and the unmet precondition. Don't report a skipped entry point as verified through another.

## Gotchas

- **The app's day ends at 05:00.** Between 00:00 and 05:00 host time, the app's "today" is *yesterday's* date. `V doctor` prints both. Don't read a day-key mismatch as a bug before checking the clock.
- On a freshly booted simulator the first day generation can take 10s+, and Today briefly shows `0 random slots` / "No quests today — the pool is empty". That is not an empty pool: `V up` waits until quests exist (60s cap); if you launch by hand, run `V doctor` until `dailyQuest` is above 0 before judging the screen.
- A tap issued right after a sheet or alert dismisses is swallowed. Screenshot first and re-tap.
- Time travel writes future-dated rows that never go away (going back doesn't undo). It is simulator-only on purpose. After a time-travel proof, `V up --fresh` to start clean.
- `Mark as done?` is a bottom sheet (the card, a full-width `Complete` pill, a quiet `Not yet`), not an inline toggle. Tap `Complete`.
- After a completion the payout card also asks "How did that feel?" (five thumbs → ratings −2…+2). Tap one to dismiss and log a rating, or the card stays up.
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
