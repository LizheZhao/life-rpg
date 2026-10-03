# Dev Plan

Stages follow `PLAN.md` §11; this file only tracks concrete checkable tasks, updated as development progresses. Design intent, formulas, and data model definitions stay authoritative in `PLAN.md` — not repeated here.

Current status (2026-09-27): **code done through Stage 5**, and most of Stage 6. Stages 3, 3.5, 4 and 5 stay open only on their device checks, which need real daily use on the phone. Stage 5 landed with the epic (incl. extension and free replace), paid reroll, Rewards tab, Library tab and rating-driven `affinity`, followed by the review follow-ups (05:00 day end, routine replace, library ad-hoc counting toward the weekly target, Sunday bill on the today page). Stage 6: JSON export / restore with confirmation and `StoreAudit`, BOM stripping done; **the web-prototype importer is next**, waiting on a sample save file. Stage 5.5 (streak milestones, level perks, savings goal) code done, 451 Core tests.

History, kept because later stages build on its contracts — Stage 1 as it stood when it closed: `ensureToday`, catch-up, sampling, scoring,
streak, the ledger, the today page, the payout reveal and the exports were in; 162 Core tests. Two inputs were stubs then,
since filled by Stages 2 and 3: `tier` was always `normal`, and `routineLoad` was always 0.

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

The `PLAN.md` §12 open questions that used to block tasks here (marked **design call**) have all been decided and folded into the stages below. What remains open in §12 — the exercise `weekly_target`, widening the H pool — needs real usage data, not code.

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
- [x] **Backlog section** on the today page: skipped and never done, newest first, read-only, with what it cost — `Schedule.backlog`. *Moved:* it is now the Calendar's collapsible "Did not finish" card for the month on show, and the day detail marks such a routine with a ring-and-cross (`RoutineStatus.missed`); a routine you paid to cancel stays `skipped` (dash) and is not in it. Told apart by the settlement's `skip` ledger entry, no schema change — `Schedule.missed(_:ledger:in:)`.
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
- [x] `degraded_text` + tests — `Core/Rules/Degrade.swift`, `DegradeTests`. Decisions made with the user: low day = `low` or `veryLow` (`Tier.isLow`, now also what `Scoring.effortMultiplier` reads); decided when the occurrence is created (do-ahead included, ad-hoc never); the original can be chosen instead for the same points until the occurrence is closed (`Degrade.choose`, "Do original" / "Use light" on the row). Done ahead, the version is picked in the confirmation instead (`completeAhead(light:)`), since there is no open row to switch afterwards. `RoutineOccurrence` gained `degradedTextSnapshot` (optional, still `SchemaV1`; export carries it); `displayText` is what the page and the ledger note show. Only exercised by tests until Stage 3 produces a real tier
- [x] Routine points get the 1.3x low-tier multiplier + tests — `Scoring.routinePoints`
- [x] Ad-hoc routine replacing a random slot + tests — `Core/Day/AdHoc.swift`, `AdHocTests`. Decisions made with the user: library **and** custom, on a separate page with two tabs (`AdHocView`, the "+" on the today page); custom base = midpoint of E/M/H; the ad-hoc occurrence is independent of the routine (`routineID` nil, never flexible, no weekly target, no `lastCompletedDayKey`), always on the fixed ladder and always gating the clear. `RoutineOccurrence` gained `replacesQuestID` / `adHocSourceRoutineID` (optional, lightweight migration, still `SchemaV1`; export carries both). `Completion.complete` / `tickTrivialItem` refuse a replaced slot
- [x] `randomSlots` dynamic calculation wired to routine load — counted inside `ensureToday`. Note: a day already generated by an older build keeps its old 3 slots and no routines; the next day is correct

## Stage 3 — HealthKit and Calendar

Done when: readiness actually drops the tier on a bad sleep day

Code is done: Core tested (`EnergyTests`, `HealthBucketsTests`, `AutoVerifyTests`, 296 Core tests), the app reads HealthKit / EventKit in `HealthService` / `CalendarService` and feeds `ensureToday` from `RootView`. Installed on the phone, HealthKit access granted, and the debug page's **Preview today's body data** (reads and scores now, writes nothing) returns real readings. **Stage 3 stays open** until the device checks below pass in daily use.

- [x] Xcode: HealthKit capability (`LifeRPG.entitlements`), `NSHealthShareUsageDescription` and `NSCalendarsFullAccessUsageDescription`. An **empty** usage description makes HealthKit throw on the permission request — it looked like a frozen app because the debugger had paused the crash
- [x] The free personal team installs an app with the HealthKit entitlement (`PLAN.md` §1). First launch needs the developer certificate trusted on the phone (Settings → General → VPN & Device Management)
- [ ] Device check: the next morning's day stores real HRV / sleep / resting HR instead of 1.000 / 75 (a day generated before access was granted stays at defaults — the tier is locked at generation)
- [ ] Device check — **the stage's "done when"**: a genuinely bad night drops the tier to low / veryLow and the day's composition follows
- [ ] Device check: preview sleep hours and resting HR agree with the Health app (the sleep window and the RHR rule below are unverified assumptions)
- [ ] Device check: a real workout written by the Shortcut auto-completes the matching routine / quest; mindful minutes likewise; a cycle day caps at normal
- [x] HealthKit read of sleep / HRV / restingHR / mindful / menstrualFlow — `HealthService`. Which samples make a day is `Core/Rules/HealthBuckets.swift`: sleep = asleep stages ending in `[D−1 18:00, D 12:00)`, overlapping sources merged (Watch + Oura); HRV = mean of that window; resting HR = latest in `[D−1 00:00, D 12:00)`. The RHR rule assumes Apple dates its daily sample on the day it describes — **unverified against real data**
- [x] energy / readiness + 28-day rolling median baseline + tests — `Core/Rules/Energy.swift`. Decisions made with the user: a missing metric (no HRV, no baseline yet) is dropped and the remaining weights renormalised; a metric needs 7 days in the window for a baseline; nothing usable → `normal`. The tier is **locked when the day is generated** (first open), like the rest of the day; the 28-day history is re-read from HealthKit each morning, which is also the first-launch backfill. Raw readings are stored on `DailyContext` (fields already existed)
- [x] Tier thresholds (0.85 → low, 0.92 and 1.06 → normal) and the composition table fed a real tier; 1.3x at low tier already in `Scoring`
- [x] Intensity ladder confirmed with the user: `veryLow` → low only, `low` → low + medium, cycle drops high
- [x] Cycle: any `menstrualFlow` sample that day other than "none"; `Energy.cap` caps high at normal, never pushes down
- [x] EventKit `calendar_workout:N` auto-verification — `Core/Day/AutoVerify.swift`. Decided with the user: an event counts only if it is in the chosen calendar **and** its title has a keyword (both set on the debug page; unset = off). All-day events never count. One event verifies one thing (routines first, oldest due first, shortest sufficient event); anything already completed that day spends its evidence first, so re-running is idempotent
- [x] `mindfulSession` auto-verification, sessions accumulate per day (drawn down as items claim them)
- [x] Auto-verify runs on every foreground for today, and during catch-up on each ended day **before** it is judged — a workout on a day the app never opened still counts on that day instead of being docked. `RoutineOccurrence` gained `sourceTypeRaw` (defaulted, still `SchemaV1`; export carries it); `Completion.complete` / `completeRoutine` take a `source`
- Not covered, by design: `calendar_workout_weekly` (the epic's, Stage 5); T groups; ad-hoc occurrences (no routine to read a rule from). A light version shorter than the routine's threshold (weight training: light 20 min, rule 40) won't auto-verify — tap it

## Stage 3.5 — one difficulty axis, cycle days, foreground re-read

Done when: the first day of a period offers a walk instead of strength training

Code done (`SchemaV2`, 337 Core tests). Four changes that belong together because they share one migration:

- [x] **`intensity` removed from both libraries** — `QuestTemplate`, `RoutineTask`, both seed CSVs, `Composition.allowedIntensities` and the `Sampling` filter. Difficulty already says how hard a thing is and the composition table is what filters a low day; for routines nothing read `intensity` at all. What this gives up: a physically demanding *easy* quest can now show up on a very-low day, since nothing separates exertion from resistance any more
- [x] **`degraded_text` → downgrade versions.** A lighter version is a `RoutineTask` row of its own, linked from its parent's `downgradeIDs` (CSV column `downgrade_of`, `|`-separated parent texts). It carries its own points, its own auto-verify rule (the walk verifies at 30 min, not the strength session's 40), and is never scheduled on its own. Several on offer → one drawn at random when the day is generated. `RoutineOccurrence` gained `degradedRoutineID` and `degradedBasePoints`
- [x] **The light version pays — and is charged — its own points.** Reverses the earlier "same points either way": otherwise the row's `base_points` is a field nothing reads. `RoutineOccurrence.effectiveBasePoints` is the one place that decides
- [x] **Cycle days 1–3 hold the tier at `low`** (`Cycle.day` + `Energy.cap`), which is what triggers the downgrade — no separate cycle rule anywhere. Counted in calendar days from the round's start, so a missed log still counts; `DailyContext.cycleDay` records it. `HealthService` reads two weeks of `menstrualFlow` instead of one day
- [x] **Body data re-read on every foreground**, and a day already on screen can be re-planned after confirming (`Replan`): finished work untouched, open slots redrawn, open routines' downgrade decision redone. A failed read never re-plans
- [x] `SchemaV2` + a lightweight migration stage; JSON export `schemaVersion` 3 (carries `cycleDay` and `degradedBasePoints`)
- [x] `SeedImporter` now also links downgrade versions onto rows the DB already has — the one thing the merge writes to an existing row, and it only ever adds an id
- [x] **T is the bottom rung of the composition table**, not an overlay on an E slot: `veryLow` = T,E,E and `low` = T,E,M; `normal` and `high` have no T. The 40% chance and the very-low guarantee are both gone, so `Composition.plan` no longer takes an RNG and `Composition.Slot` is gone with it — a planned slot is just a `Difficulty`. A T-group `DailyQuest` now records `slot = .trivial` instead of `.easy`; history rows written before this keep `.easy`, which only affects how they sort in the day detail. Settles the T-probability question in `PLAN.md` §12. **Consequence: micro-actions no longer appear on normal or high days at all**
- [x] Re-plan keeps open slots the new table still asks for, and drops only what it no longer has — the first version redrew every unfinished row, so a cycle day swapped a T group for a different T group. Found on the phone on 2026-09-23, cycle day 2. `DailyQuest` gained `replacedReason` (optional, lightweight; nil reads as `.adHoc`, which every earlier row was), so the page stops calling a re-plan an ad-hoc replacement. A tier change that would leave the page identical is no longer offered
- [ ] Device check: on the phone, a real day 1 shows the walk instead of weight training, and the day detail says "cycle day 1"
- [ ] Device check: opening the app before the watch has synced, then again after, offers the re-plan and doesn't disturb anything already done

## Stage 4 — Monthly calendar page

Done when: any past day can be reviewed

Code done: `Core/Rules/CalendarMarks.swift`, `Core/Time/MonthGrid.swift`, `Core/Day/DayRecord.swift` (`CalendarMarksTests`, `MonthGridTests`, `DayRecordTests`, 317 Core tests); app pages `CalendarView`, `DayDetailView`, `RatingSummaryView`, a Calendar tab in `RootView`. Checked on the simulator. No `@Model` change.

- [x] Month view: green dots (random quests done, 0–3; hidden / epic / replaced don't count, the T group counts once), blue dot, star (hidden). **Blue dot decided with the user:** every `countsForClear` routine due that day done **on the day** — done ahead counts, a late make-up or a skip does not, and a day with no gating routine shows no blue dot. Deliberately stricter than `hiddenUnlocked`, which treats a skip as cleared
- [x] Epic-completed week highlight, judged by `weekKey` (not row index) — `CalendarMarks.epicWeeks`. Monday-start grid so each row is one ISO week and carries its `weekKey`. Nothing lights up until Stage 5 generates epics
- [x] Custom `LazyVGrid` (not `UICalendarView`)
- [x] Day detail sheet: quest/routine status, points, completion time, auto-verify/degraded markers, that day's redemptions and penalties, `DailyContext`. Late make-ups and done-ahead routines also appear on the day the work happened ("Done this day for another day")
- [x] Day detail shows the ratings given that day, hung on the completion that prompted them via `QuestRating.questID`. **Design call decided:** rerolled-away rows are shown too, so Stage 5's reroll **must** keep them (see Stage 5). The display itself waits for the `rerolledAway` field
- [x] Summary view over the rating log (`RatingSummaryView`, 7 / 30 / 90 days / all, via `Feedback.topRated(since:)`) — still unchecked against real ratings
- [ ] Device check: open a few real past days on the phone and compare against what happened

## Stage 5 — Epic, paid reroll, redemption

- [x] Epic generation (every Monday, visible immediately), extension (max twice) — `Core/Day/Epic.swift`, `EpicTests`. Drawn by `ensureToday` on the first day of the week the app generates (Monday, or the first day opened), outside the composition table. **Decided with the user:** at most one epic live at a time — an extended epic runs into the next week and that week draws none; the calendar highlights the week it was **completed** in (`CalendarMarks.epicWeeks` reads `completedAt`, not `weekKey`); an unfinished epic just runs out after its last Sunday, no penalty, row kept. Completion books the payout and cooldown to the day it was done. Extension: 400 (since lowered to 50, see review follow-ups) as a `redeem` entry, same balance rule as a reroll. The previous week's epic is left out of the draw unless it is the only one. Today page: own section above routines, with the extend button
- [ ] Device check: an epic appears on Monday, stays all week, extend once and watch next Monday draw nothing
- [x] Reroll **pricing and the balance rule** + tests — `Core/Rules/Reroll.swift`. Cost is settled; the swap itself is still below. A reroll may never take the balance below zero (exactly zero is allowed), and is refused outright while in debt
- [x] Reroll **execution** — `Reroll.perform`, `RerollPerformTests`. The old row is kept, marked `replaced` with the new `ReplacedReason.rerolled` rather than a separate `rerolledAway` field: no `@Model` change, and full clear, streak, calendar dots, ad-hoc, re-plan and auto-verify already skip `replaced` rows. The new row carries `rerollCount + 1`; nothing the day already served (swapped-away rows included) is drawn again, and an empty pool refuses without charging. Hidden is never rerollable, a regular slot only on its own day. Today page: swipe left on a slot → confirm; rerolled-away rows are hidden there and shown as "Rerolled away" in the day detail
- [x] Epic reroll, a flat 80 each time. **Decided with the user:** any number of rerolls until the epic is extended, none after (`Purchase.Blocked.epicExtended`) — paying to keep it and then swapping it away would waste the extension. The replacement keeps the old row's `dayKey`, so the deadline doesn't move, and never repeats an epic already on the page this week. Booked to the day it happened. Today page: a reroll that can't go through is greyed out; one refused only at draw time (empty pool) gets a popup saying nothing was charged
- [x] `Reward.estimatedCost` → coins conversion formula + tests — `Core/Rules/RewardPricing.swift`. One `multiplier` (10); above 500 each unit is worth half. Rounded up. Virtual items use `fixedCoins`. The PLAN table is asserted literally
- [x] Redemption page UI, reroll disabled while balance is negative — `RewardsView` (new tab, **new file: confirm it in Xcode**). **Decided with the user:** rewards are entered by hand (name + real cost; coins always computed, never typed), archived rather than deleted, repricing never touches past redemptions. Redeeming is one `redeem` entry, same balance rule as everything else (`Purchase.blocked`, shared by reroll, extension, cancel, freeze and rewards). Reroll, cancel and the epic extension are **not** on this page — they are swipe actions on the rows they act on, greyed out when they can't go through
- [x] Ad-hoc split in two (decided with the user): **Replace** is a swipe action on each replaceable random slot (`AdHocView` opened with that slot); the today page's **+** now adds a routine on top of the day, replacing nothing — `AdHoc.add`, `countsForClear = false`: doesn't gate hidden, never charged, pays when done
- [x] Virtual item redemption — `Core/Day/Redemption.swift`, `RedemptionTests`, no `@Model` change:
  - Cancel a quest (E 120 / M 250 / H 450): today's open regular slot only — not T, hidden or epic. Marked `replaced(.cancelled)`: stops gating the clear, earns nothing, no streak day
  - Cancel a routine (200): an open **fixed**, clear-gating routine due today or overdue. Closed as `skipped` (no further deductions; earlier ones stay); the `redeem` entry is what tells it from giving up. Flexible routines can't be cancelled — they already move freely within the week, and Sunday's settlement would count the cancelled session as missing
  - Streak freeze (300): **bought after the break to patch it** (decided with the user). Only for a single missed day right behind the current run (`Streak.repairableDay`); it bridges the run without counting as a day. Booked as a `freeze` ledger entry dated **the day it covers** — the one entry not dated the day it happened, which is how `Streak.frozenDayKeys` finds it. Offered on the Rewards page only when there is a day to cover
  - Epic extension: done with the epic, now a swipe action on the epic row
- [x] Quest library management UI: rating and comment entry — `LibraryView` (new tab, **new file: confirm it in Xcode**). Quests grouped by difficulty, routines, searchable; each row shows the latest rating and note count. Detail: rate on the same five-step scale as the payout reveal (`RatingScale.steps`), notes, and both logs newest first. Every rating and note appends (`questID` nil — not tied to a completion). Array overloads `Feedback.latestRatings(_:)`, `.ratings(_:for:)`, `.comments(_:for:)` so the page passes its `@Query` rows. Scope as written here: no template editing or (de)activation
- [x] Feed ratings back into `QuestTemplate.affinity`, which is what sampling actually weights on — `Core/Rules/Affinity.swift`, `AffinityTests`. **Decided with the user:** mean of the last 3 ratings, rounded (.5 away from zero). `Affinity.sync` runs in `ensureToday` before the draw and after every rating (payout reveal, Library)
- [ ] Device check: epic across a week boundary (draw, extend, next Monday draws nothing), a real reroll / cancel / freeze / redemption with enough coins, and a rating moving the next day's draw
- [x] Review follow-ups (decided with the user, 2026-09-27):
  - Day ends at **05:00**, not midnight — `LifeCalendar.dayStartHour`, applied inside `Date.dayKey` / `weekKey`, so every caller moves with it; `Date.calendarDayKey` for HealthKit period samples only. No `@Model` change
  - Epic extension 400 → **50** (below the payout on purpose: it buys time, not less work)
  - **Epic replace** — `Epic.replace`, free: a library epic or a hand-written one, keeps the deadline, old row `replaced(.swapped)` (new `ReplacedReason`); blocked once done or extended. `EpicReplaceView` sits in `AdHocView.swift` (no new file)
  - **Routine replace** — `AdHoc.replaceRoutine`, free for something at least as heavy (`Failure.tooLight`). New optional `RoutineOccurrence.replacedByID` (lightweight migration fills nil). Fixed: keeps the due day, the ladder carries on. Flexible: due today; the swapped session leaves the week's target (`Overdue.weekly`)
  - Ad-hoc tasks picked from the library count toward that routine's weekly target — `Schedule.doneThisWeek`, used by scheduling, do-ahead and Sunday settlement
  - Today page: "Ahead this week" open by default on Sat/Sun, header shows Sunday night's bill from `Overdue.weekly` (same rule as the settlement); skipped/cancelled routine rows no longer offer "Done"
  - Ad-hoc sheet no longer hides routines already on the page: they are listed with where they are and a Done button (`AdHoc.onPageOccurrence`); a custom task shows similar library routines as it is typed (`AdHoc.similarRoutines`, word / prefix / CJK-character overlap)
- [ ] Device check: open the app 00:00–05:00 and confirm nothing is settled; replace an overdue routine and an epic; watch the Sunday bill drop as flexible sessions are done

## Stage 5.5 — Streak milestones, level perks, savings goal

Done when: streak and level change what you do, not just what the HUD says. Design in `PLAN.md` §6 ("Level", "Streak milestones", "Savings goal"), decided with the user 2026-09-27/28: milestones pay coins; a fixed perk track; A + B + D of the economy review first, the prize box and crits later if at all.

Code done: `Core/Rules/Perks.swift`, `Core/Rules/StreakMilestone.swift`, `Core/Rules/SavingsGoal.swift` (`PerksTests`, `StreakMilestoneTests`, `SavingsGoalTests`, 451 Core tests). Checked on the simulator: the level track sheet, pinning a goal and its HUD bar, the level-up card on crossing Lv 2, the V2 → V3 store migration on existing data.

- [x] `Economy.Kind.streak` + `StreakMilestone` — table asserted as literals (7→50, 14→100, 30→250, 60→400, 100→600, 130/160/…→300); `Streak.runStart`; `settle` pays every reached-and-unpaid threshold of the current run, idempotent. The threshold is read back from the entry's `note` ("Streak 30")
- [x] `settle` runs after `Completion.complete` (not for the epic) — which auto-verify goes through too — and after a freeze. A failure there doesn't undo the completion; the bonus stays due for the next settle
- [x] `Perks` — the fixed track (`Perks.track`, `newlyUnlocked`) and one function per number it changes. `Economy.earnedNeeded(forLevel:)`, `Economy.level(_:)` for the level in force
- [x] Perks wired in: `Reroll.cost` / `blocked` (free = 0-point `reroll` entry, `Reroll.freeRerollsUsed`, still advances `rerollCount`, still refused in debt), `Epic.maxExtensions(level:)`, `Scoring.routinePoints(…, level:)` / `Completion.routinePayout(…, level:)` (base 50 late → 25, 30 from Lv 8), `Redemption.freezeCost(covering:level:ledger:)` (monthly free one keyed on the covered day's month). Every level parameter defaults to 1; the actions read the level from the store themselves. Existing reroll / epic tests now fund with a `grant`, which doesn't buy a level, so they keep testing level-1 prices
- [x] `Reward.isGoal` (**`@Model` change**, `Bool = false`, lightweight; `SchemaV2` → `SchemaV3`). Export / import carry it as an optional `RewardRow.isGoal` — the export's `schemaVersion` stays 3, because import refuses any other version and a bump would orphan every existing backup. `SavingsGoal`: pin (unpins the rest), unpin on redeem and on `Redemption.archive` (new; the Rewards page used to flip `isActive` itself), `pace` = net of the last 28 days ÷ 4 without the grant, `weeksLeft`
- [x] Today page: goal bar under the balance, tap the level for the track, one alert for a level-up and / or new streak bonuses — held back while the payout reveal is up; what was last announced lives in `@AppStorage`. The level header on the epic shows the level's max extensions; the reroll swipe reads "free" when it is
- [x] Rewards page: swipe right to set / unpin the goal (flag on the row); the freeze button shows its real price (free / 150 / 300)
- [ ] Device check: a 7-day milestone card on the phone; a free reroll at Lv 3 writes a 0-point entry; the goal's weeks-left moves after a reroll-heavy day

## Stage 6 — Backup and migration

Done when: balance matches exactly

- [x] Export through `fileExporter` (iCloud Drive is one of its destinations), dated filename, `schemaVersion` — already true of the Stage 1 export. It now also carries `library` (each template / routine's old id, text and cooldown / schedule stamps) and `rewards`, plus `launchURLSnapshot` and `degradedRoutineID` it had been missing. All optional in `Snapshot`, no `@Model` change, so `schemaVersion` stays 3
- [x] JSON import + confirm before overwrite — `Core/Import/JSONImport.swift`, `JSONImportTests`. `plan` decodes, checks the version and maps ids without writing; the today page's export menu → **Restore from JSON…** shows its summary (days covered, row counts, the balance after) and asks. `apply` replaces every history table wholesale, restores the stamps, re-derives `affinity`. Decided with the user: a reinstall reseeds with new UUIDs, so old ids are re-pointed at the row with the **same text**; an id whose text the library no longer has stays as it was and is listed in the summary. Exports without `library` (written before import existed) are refused as too old. **Done-when test:** export → reinstall-like fresh store with its own grant and day → import, balance and total earned equal the source's
- [ ] One-time importer for the web prototype's save data — waiting on a sample save file from the user; the format is only described in `PLAN.md` §10, not enough to write a parser against
- [x] 100-coin opening grant, once ever, keyed on an existing `grant` entry so an import doesn't mint a second — `Economy.grantStartingBalanceIfNeeded`. Excluded from `totalEarned`: spendable, but it doesn't buy a level
- [x] Rating asked right after the payout reveal, carrying `questID` so it points at the one completion that prompted it — `DailyQuest` stays the record of *what happened*, `QuestRating` of *how it felt*, and the summary page joins them. Optional and one tap; the card closes itself after 8s if untouched
- [x] `QuestRating` / `QuestComment` tables + `Feedback` queries + CSV export of both logs — `Core/Rules/FeedbackLog.swift`, `Core/Export/CSVExport.swift`, share menu on the today page. Pulled forward for the same reason as the JSON export: ratings and comments exist nowhere else, so they must not start accumulating without a way off the device. Append-only and dated, so "what have I been rating highest lately" stays answerable
- [x] JSON export carries the feedback logs (`schemaVersion` 2)
- [x] `StoreAudit.issues` scans for unknown enum raw values, unparseable specs and malformed day/week keys (the `?? .easy` getters fall back silently); shown on the debug page
- [x] `StoreAudit.issues` runs after the import is staged and before `save`; any issue rolls the whole import back and is reported, the store untouched
- [x] Strip a UTF-8 BOM in `CSV.records` (Excel / Numbers), `SeedParserTests.byteOrderMarkIsStripped`
- [ ] Device check: export on the phone, restore it (ideally after a reinstall), balance unchanged; restore picker + confirmation look right

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
