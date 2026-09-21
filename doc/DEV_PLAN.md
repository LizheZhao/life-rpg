# Dev Plan

Stages follow `PLAN.md` §11; this file only tracks concrete checkable tasks, updated as development progresses. Design intent, formulas, and data model definitions stay authoritative in `PLAN.md` — not repeated here.

Current status: Stage 2 in progress — scheduling, occurrences, load → slots, routine completion, the overdue ladder, day-4 auto-skip, flexible Sunday settlement, the backlog and doing a flexible routine ahead are in, plus a two-week scenario test and simulator-only time travel (223 Core tests). Left: degraded_text, ad-hoc replacement. Stage 1 below as it stood: done, reviewed, and extended. `ensureToday`, catch-up, sampling, scoring,
streak, the ledger, the today page, the payout reveal and the exports are in; 162 Core tests. Two inputs are still stubs, by
design: `tier` is always `normal` until Stage 3 reads HealthKit, and `routineLoad` is always 0
until Stage 2 schedules routines — both are `DayInputs` parameters, so wiring them is a one-line
change at the call site. Next: Stage 2 (frequency scheduling, overdue penalty, flexible weekly
settlement).

The Stage 1 review turned up four things worth recording, because three of them set contracts
Stage 2 builds on:

- **Catch-up settled the wrong days.** The range was `(lastProcessed, today]` — it judged today,
  which isn't over, and never judged the last day the app actually saw. It is now
  `[lastProcessed … yesterday]`. With an empty `settle` closure this changed nothing visible; once
  the overdue penalty hangs off it, it is the difference between a routine being docked at 8am and
  being judged after the day ends.
- **`countsForClear` was never read.** `hiddenUnlocked` treated every routine occurrence as gating
  the day. `RoutineOccurrence` now snapshots the flag and the check filters on it.
- **`variants` was dead data.** Parsed from the CSV, stored, never read. Three seed rows depend on
  it, and `textSnapshot` is written once — history recorded without the variant could not be
  backfilled later.
- **A completion that failed to save left a lie on screen.** Points and `completedAt` were written
  before `context.save()` and not rolled back on failure.

One review finding did **not** hold up: the confirmation alert reading `pending` back out of
`@State` inside the button was tested on the simulator and works — SwiftUI runs the action before
the dismissal clears the state. It was rewritten to `alert(_:isPresented:presenting:)` anyway, as
hardening against an ordering nothing documents, not as a bug fix.

Two items below are marked **design call** — they're the remaining `PLAN.md` §12 open questions,
each blocking a specific task rather than a whole stage. Everything around them can be built first.

---

## Stage 0 — project, model, seed

Done when: DB has data and the app runs

- [x] Create `LifeRPGCore/Package.swift` (confirm target/product layout first)
- [x] Define enums: `Difficulty` `Intensity` `Tier` `RecurrenceKind`
- [x] Define `@Model`s: `QuestTemplate` `RoutineTask` `DailyQuest` `RoutineOccurrence` `Reward` `LedgerEntry` `DailyContext`
- [x] CSV importer: read `side_quests.csv` / `routine_quests.csv` into `QuestTemplate` / `RoutineTask` (map `T/E/M/H/EPIC` → rawValues, honor `is_active` and `weekend_only`)
- [x] `swift build` / `swift test` run successfully (15 tests)
- [x] `SchemaV1: VersionedSchema` + empty `LifeRPGMigrationPlan`; startup failure shows `StartupErrorView` instead of crashing, store untouched
- [x] `SeedImporter.mergeSeeds`: additive merge keyed on `text` (edits and soft-deletes in the app always win)
- [x] Xcode project `LifeRPG.xcodeproj` created, links local package, bundles `doc/*.csv` (symlinks in `LifeRPG/Seed/`), seeds on first launch

## Stage 1 — Today page MVP

Done when: ready for daily use

- [x] `dayKey` (Gregorian) / `weekKey` (ISO 8601) helper functions + tests (year boundary, region-independent, midnight-DST round trip) — `Core/Time/DayKey.swift`, incl. `range(after:through:)` for the catch-up loop
- [x] `ensureToday`: random slot count calculation and generation; idempotent via `DailyContext`; injected `now` / RNG + tests — `Core/Day/DayService.swift`. Idempotency is keyed on `DailyContext`, so a day where every draw came back nil still counts as generated
- [x] Catch-up over missed days + tests — `DayService.catchUp`, with the per-day work passed in as a `settle` closure for Stage 2 to fill; only today is generated, days slept through stay empty. The range is `[lastProcessed … yesterday]`: **today is never settled** (it isn't over), and the last day the app saw **is** (it was generated but nothing judged it before the day ran out)
- [x] `sample()` draw logic (cooldown from completion day, 1-day cooldown for drawn-but-not-done, weights by affinity) + tests — `Core/Rules/Sampling.swift`
- [x] Parameterized templates: one value drawn from `variants` at generation and snapshotted as `DailyQuest.variantSnapshot` (and `trivialVariants` for the T group) + tests — kept beside the text, not spliced into it, so the CSV wording stays the row's identity and the seed merge still keys on it
- [x] T group takes one E slot, scored 12 as a whole + tests. Needed one additive field, `DailyQuest.trivialTemplateIDs`, so all three templates get their cooldown written back
- [x] `weekendOnly` templates excluded Mon–Fri + tests
- [x] **Design call — settled** — weekend H exposure (`PLAN.md` §12): fewer slots drop from the **hard** end (1 slot at `normal` = E, 2 = E + M), weekends included. No H guarantee: putting the hardest random quest on the heaviest routine day would undo the point of the dynamic slot count. Revisit with real data
- [x] Streak: consecutive days with ≥1 random quest completed + tests — recomputed from completed `DailyQuest` rows, never stored; a day with nothing done yet still shows yesterday's run
- [x] `awardedPoints` roll logic (1.3x on low tiers, rounded; hidden +10 not multiplied) + tests — `Core/Rules/Scoring.swift`
- [x] `LedgerEntry` bookkeeping, balance derived by sum — `Core/Rules/Economy.swift`, incl. level and points-to-next-level
- [x] Minimal SwiftUI today page: quest list, complete button, hidden reveal. **No undo** — completion is final (`PLAN.md` §3), so each tap is confirmed once
- [x] HUD: balance (red when negative), level, streak, tier, slot count
- [x] Payout reveal on completion: the number shakes through a few throwaway values and lands, hidden's flat +10 flies in afterwards, the T group is labelled as a fixed payout rather than miming a roll — `LifeRPG/PointsRollView.swift` + `Scoring.Breakdown`. It is **presentation only**: the roll already happened inside `Completion.complete` and is already in the ledger, and `breakdown` takes the awarded value as a parameter so a view physically cannot re-roll it
- [x] Difficulty badge shows what the slot can pay (`5–15`, `25–50`, `15–25` for a hidden E), tier multiplier and hidden bonus already applied — `Scoring.payoutRange`, the same arithmetic the roll obeys, with a test that rolls E/M/H/EPIC × every tier × hidden 60 times each and checks the result lands inside what the badge advertised
- [x] Rating asked on the same card, one tap, skippable, `questID` attached — see Stage 6
- [x] 100-coin opening grant — see Stage 6
- [x] Reroll **pricing** — see Stage 5
- [x] Debug "Reopen today": marks today's quests undone, deletes the ledger entries that paid for them, removes the hidden row so it can be revealed again, and clears the templates' completion stamps — `Core/Day/DayReset.swift`. Deliberately on the debug page and not the today page: a reset button beside the quests would undo `PLAN.md` §3 in practice whatever the doc says
- [x] Raw store-file export from `StartupErrorView` (`fileExporter`, bypasses SwiftData, exports `.store` + `-wal` + `-shm` as one folder) — the rescue path when a migration fails. Not exercised at runtime yet: it only appears when the container fails to open
- [x] Save failures roll back: a quest is shown as done only once its ledger entry is actually on disk — `Completion.complete` restores `points`, `completedAt` and the template cooldown and deletes the entry if `save()` throws
- [x] **Minimal JSON export** (manual button, dumps `LedgerEntry`/`DailyQuest`/`RoutineOccurrence`/`DailyContext` to a file, no import yet) — `Core/Export/JSONExport.swift` + the share button on the today page; carries `schemaVersion`. Templates and routines are left out on purpose: they rebuild from the seed CSVs, history does not. Pulled forward from Stage 6: until CloudKit exists, real usage data only lives in this one app's sandbox on the phone, so don't start accumulating history without a way to get it off-device first

## Stage 2 — Routine layer

Done when: Saturday no longer stacks up to ten tasks

**This is the next thing to build, and the gap it closes is bigger than it looks.** `routineLoad`
is hard-coded to 0, so `Composition.slots` always returns 3 — every day gets the full three random
quests. On a Sunday with four routines due it should be two, and on a heavy Saturday one. Until
scheduling exists the app hands out more random work than the design intends, on exactly the days
that already have the most routine work.

- [x] Frequency **spec parsing + validation**: weekly / everyNDays / monthly / nthWeekdayOfMonth / everyNWeeksOnWeekday + tests — `Core/Rules/FrequencySpec.swift`, called from `SeedParser` so `TUES` or `1:SATURDAY` throws with a line number
- [x] `auto_verify` rule parsing + validation (`mindful:N` / `calendar_workout:N` / `calendar_workout_weekly:N`) — `Core/Rules/AutoVerifyRule.swift`, same import gate
- [x] Frequency **scheduling** + tests — `Core/Rules/Schedule.swift`, `ScheduleTests` (incl. the seed's load for a whole week, Fri 1 / Wed 3 / Sat 5 per `PLAN.md` §3). Decisions made with the user:
  - `nthWeekdayOfMonth` takes n = 1…4 or -1; `5:SAT` is now rejected at import (most months have no fifth Saturday — use `-1:SAT`)
  - `everyNDays`: never completed → due at once; otherwise due `lastCompleted + N`. Not re-issued while its round is open (days 1–3); a skipped round ends on day 4 and the count restarts from that day — an undone routine is **not** chased every day
  - `everyNWeeksOnWeekday`: `anchorWeekKey` is set by the routine's **first completion** (`Completion.completeRoutine`); before that it is due every week on its weekday
  - Overdue routines do **not** count toward the day's load; only routines due that day do
- [x] `ensureToday` inserts today's `RoutineOccurrence`s (text / points / `countsForClear` snapshotted) and counts `routineLoad` from them. `DayInputs.routineLoad` was removed so the load can't be computed in two places
- [x] Routine completion — `Completion.completeRoutine`: `round(base × m)` on the due day, `round(base × 0.5 × m)` on day 2–3, refused before the due day and from day 4; rolls back on a failed save like `complete`. Today page shows routines (overdue pinned on top, "day N of 3 · half pay") with a confirmed Done button
- [x] **Backlog section** on the today page: skipped and never done, newest first, read-only, with what it cost — `Schedule.backlog`
- [x] Overdue penalty + tests — `Core/Day/Overdue.swift`, run by catch-up for every ended day (`ensureToday` uses it by default). 50% / 75% / 100% of base, stacking, no daily cap, day-4 auto-skip with a 0-point `skip` entry dated day 4; `countsForClear = false` never charged. Idempotent per (occurrence, day) via the ledger. Today page marks overdue rows "Overdue −50%" in red
- [x] **Design call — settled** — the overdue penalty is **not** scaled by readiness or tier: fixed on base
- [x] Late make-up on day 2–3: half of base × multiplier, skips that day's deduction (falls out: it is no longer open when that day is judged), not counted for full-clear + tests
- [x] **Design call — settled** — flexible routines: a single deduction on Sunday, 50% of base per occurrence short of `weekly_target`; no escalation into the next week, no daily ladder
- [x] `flexible_within_week` weekly settlement + tests. Target is capped by how many occurrences actually came due that week (a day the app never opened generates none, same as fixed routines). A flexible occurrence can be completed at full pay any day from its due day to that Sunday; open ones from earlier in the week show as "This week"
- [x] **Design call — settled (B)** — doing a flexible routine **earlier** than its due day logs ahead against the next occurrence still to come this week
- [x] Flexible do-ahead + tests — `Schedule.aheadCandidates` / `Completion.completeAhead`, `FlexibleAheadTests`. Offered when the routine is short of target this week, has nothing open on the page, and still comes due later this week. Creates that occurrence completed today at full pay; on its due day it is not generated again and doesn't count toward load. Today page: "Ahead this week" section with a confirmed "Do now"
- [x] Review fixes: a flexible routine whose `weekly_target` is met this week (ahead included) stops coming due for the rest of the week (`Schedule.dueRoutines`); a do-ahead first completion sets the `everyNWeeksOnWeekday` anchor like any other (`Completion.stamp`, shared by both paths). **Design call — settled:** a flexible routine due today still gates that day's hidden quest
- [x] Scenario tests — `ScenarioTests`: two weeks with the real seed through `ensureToday` (late make-ups, moved and ahead flexible sessions, days never opened, a low-tier day, first/last-Saturday loads), every balance worked out by hand; opening twice a day changes nothing; a week of doing nothing costs exactly the hand-summed ladder
- [x] Debug time travel, **simulator only** (`#if targetEnvironment(simulator)`): "Advance one day" / "Back to the real date" on the debug page; `RootView` shifts `now` by the offset. Future-dated rows stay after going back — delete the app to start clean
- [ ] `degraded_text` fallback logic (auto-swap on low energy, only routines with `degraded_text`)
- [x] Routine points get the 1.3x low-tier multiplier + tests — `Scoring.routinePoints`
- [ ] Ad-hoc routine replacing a random slot (`replaced` flag)
- [x] `randomSlots` dynamic calculation wired to routine load — counted inside `ensureToday`. Note: a day already generated by an older build keeps its old 3 slots and no routines; the next day is correct

## Stage 3 — HealthKit and Calendar

Done when: readiness actually drops the tier on a bad sleep day

- [ ] HealthKit permissions + read sleep / HRV / restingHR / mindful / menstrualFlow
- [ ] energy / readiness calculation + 28-day rolling median baseline + tests
- [ ] Tier thresholds and random composition table, 1.3x effort multiplier at low tier — the table itself is already in `Core/Rules/Composition.swift`; Stage 3 only has to feed it a real tier
- [ ] Confirm the intensity ladder `Composition.allowedIntensities` assumes (`veryLow` → low only, `low` → low + medium, cycle drops high). `PLAN.md` §5 fixes only the cycle rule and "filter down at low energy"; the middle step is this app's reading of it
- [ ] Cycle detection: tier capped at normal, excludes `intensity = high`
- [ ] EventKit reads calendar, `calendar_workout:30` auto-verification
- [ ] `mindfulSession` auto-verification (allows multiple sessions per day to accumulate)

## Stage 4 — Monthly calendar page

Done when: any past day can be reviewed

- [ ] Month view: green dot (random quests completed), blue dot (routines fully done), star (hidden)
- [ ] Epic-completed week highlight, judged by `weekKey` (not row index)
- [ ] Custom `LazyVGrid` (not `UICalendarView`)
- [ ] Day detail sheet: quest/routine status, points, completion time, auto-verify/degraded markers, that day's redemptions and penalties, `DailyContext`
- [ ] Day detail also shows the ratings given that day (`QuestRating.questID` links each one to the completion that prompted it) and what was rerolled away — **design call**, `PLAN.md` §12: whether these appear decides whether Stage 5's reroll must keep the swapped-away rows
- [ ] Summary view over the rating log: `Feedback.topRated(since:)` already answers "what has been landing well lately" and is untested against real data — no UI yet

## Stage 5 — Epic, paid reroll, redemption

- [ ] Epic generation (every Monday, visible immediately), extension (max twice)
- [x] Reroll **pricing and the balance rule** + tests — `Core/Rules/Reroll.swift`. Cost is settled; the swap itself is still below. A reroll may never take the balance below zero (exactly zero is allowed), and is refused outright while in debt
- [ ] Reroll **execution**: mark the old row `rerolledAway` rather than overwriting it — escalation has to accumulate on the day's slot, but overwriting would erase what was swapped away, and `DailyQuest` is the history the summary page reads. The new row carries `rerollCount + 1`; `hiddenUnlocked` and `Streak` must skip rerolled-away rows the way they skip `replaced` ones
- [ ] Epic reroll fixed at 80/week (needs the epic itself, above)
- [ ] `Reward.estimatedCost` → coins conversion formula + tests
- [ ] Redemption page UI, reroll disabled while balance is negative
- [ ] Virtual item redemption (cancel a quest, epic extension, streak freeze)
- [ ] Quest library management UI: rating and comment entry, writing into the `QuestRating` / `QuestComment` logs (the tables, `Feedback.rate` / `.comment` / `.topRated` / `.latestRatings` and both exports already exist — only the entry screens are missing)
- [ ] Feed the latest rating back into `QuestTemplate.affinity`, which is what sampling actually weights on

## Stage 6 — Backup and migration

Done when: balance matches exactly

- [ ] Upgrade the minimal export from Stage 1 to real `fileExporter` to iCloud Drive, dated filename, includes `schemaVersion`
- [ ] JSON import + confirm before overwrite
- [ ] One-time importer for the web prototype's save data
- [x] 100-coin opening grant, once ever, keyed on an existing `grant` entry so an import doesn't mint a second — `Economy.grantStartingBalanceIfNeeded`. Excluded from `totalEarned`: spendable, but it doesn't buy a level
- [x] Rating asked right after the payout reveal, carrying `questID` so it points at the one completion that prompted it — `DailyQuest` stays the record of *what happened*, `QuestRating` of *how it felt*, and the summary page joins them. Optional and one tap; the card closes itself after 8s if untouched
- [x] `QuestRating` / `QuestComment` tables + `Feedback` queries + CSV export of both logs — `Core/Rules/FeedbackLog.swift`, `Core/Export/CSVExport.swift`, share menu on the today page. Pulled forward for the same reason as the JSON export: ratings and comments exist nowhere else, so they must not start accumulating without a way off the device. Append-only and dated, so "what have I been rating highest lately" stays answerable
- [x] JSON export carries the feedback logs (`schemaVersion` 2)
- [x] `StoreAudit.issues` scans for unknown enum raw values, unparseable specs and malformed day/week keys (the `?? .easy` getters fall back silently); shown on the debug page
- [ ] Call `StoreAudit.issues` after a JSON import and block/report before committing the import
- [ ] Low priority — strip a UTF-8 BOM in `CSV.records`, only needed if a seed CSV ever comes out of Excel or Numbers. Today it fails loudly as `missingColumn("text")` on the debug page rather than corrupting anything (`stage0-dev-review.md`, "Deliberately not fixed")

## Stage 7 — Optional

- [ ] Oura API v2 integration (`/v2/usercollection/daily_readiness`, token via Keychain)
- [ ] DeviceActivity threshold check (auto-verify reading)
- [ ] Notifications
- [ ] Widget
- [ ] CloudKit (requires paid account)

---

## Acceptance checks (throughout)

- [ ] Quests refresh correctly across midnight
- [ ] Manually change system time to test: streak, reroll reset, flexible routine weekly settlement
- [ ] Export JSON, reinstall, and import completely
- [ ] Verify the rescue export for real: break the container on purpose (bump `SchemaV1` without a migration stage, or corrupt a copy of the store), confirm `StartupErrorView` appears and the exported folder contains `.store` + `-wal` + `-shm` — it's the one screen that can't be reached in normal use
