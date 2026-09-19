# Dev Plan

Stages follow `PLAN.md` §11; this file only tracks concrete checkable tasks, updated as development progresses. Design intent, formulas, and data model definitions stay authoritative in `PLAN.md` — not repeated here.

Current status: Stage 0 done — app builds and seeds 75 quests / 13 routines on first launch (idempotent). Next: Stage 1.

---

## Stage 0 — project, model, seed

Done when: DB has data and the app runs

- [x] Create `LifeRPGCore/Package.swift` (confirm target/product layout first)
- [x] Define enums: `Difficulty` `Intensity` `Tier` `RecurrenceKind`
- [x] Define `@Model`s: `QuestTemplate` `RoutineTask` `DailyQuest` `RoutineOccurrence` `Reward` `LedgerEntry` `DailyContext`
- [x] CSV importer: read `side_quests.csv` / `routine_quests.csv` into `QuestTemplate` / `RoutineTask` (map `T/E/M/H/EPIC` → rawValues, honor `is_active` and `weekend_only`)
- [x] `swift build` / `swift test` run successfully (15 tests)
- [x] Xcode project `LifeRPG.xcodeproj` created, links local package, bundles `doc/*.csv` (symlinks in `LifeRPG/Seed/`), seeds on first launch

## Stage 1 — Today page MVP

Done when: ready for daily use

- [ ] `dayKey` (Gregorian) / `weekKey` (ISO 8601) helper functions + tests (year boundary, region-independent)
- [ ] `ensureToday`: random slot count calculation and generation; idempotent via `DailyContext`; injected `now` / RNG + tests
- [ ] Catch-up over missed days (settle every dayKey since last processed) + tests
- [ ] `sample()` draw logic (cooldown from completion day, 1-day cooldown for drawn-but-not-done, weights by affinity) + tests
- [ ] T group takes one E slot, scored 12 as a whole + tests
- [ ] `weekendOnly` templates excluded Mon–Fri + tests
- [ ] Streak: consecutive days with ≥1 random quest completed + tests
- [ ] `awardedPoints` roll logic (1.3x on low tiers, rounded; hidden +10 not multiplied) + tests
- [ ] `LedgerEntry` bookkeeping, balance derived by sum
- [ ] Minimal SwiftUI today page: quest list, complete checkbox, undo
- [ ] HUD: balance, level
- [ ] **Minimal JSON export** (manual button, dumps `LedgerEntry`/`DailyQuest`/`RoutineOccurrence`/`DailyContext` to a file, no import yet) — pulled forward from Stage 6: until CloudKit exists, real usage data only lives in this one app's sandbox on the phone, so don't start accumulating history without a way to get it off-device first

## Stage 2 — Routine layer

Done when: Saturday no longer stacks up to ten tasks

- [ ] Frequency parsing: weekly / everyNDays / monthly / nthWeekdayOfMonth / everyNWeeksOnWeekday + tests
- [ ] Overdue penalty (routines only; escalating 50% / 75% / 100% per undone day, stacking; day 4 auto-skip; no daily cap) + tests
- [ ] Late make-up on day 2–3: half of base × multiplier, skips that day's deduction, not counted for full-clear + tests
- [ ] `flexible_within_week` weekly settlement (shortfall judged on Sunday) + tests
- [ ] `degraded_text` fallback logic (auto-swap on low energy, only routines with `degraded_text`)
- [ ] Routine points get the 1.3x low-tier multiplier + tests
- [ ] Ad-hoc routine replacing a random slot (`replaced` flag)
- [ ] `randomSlots` dynamic calculation wired to routine load

## Stage 3 — HealthKit and Calendar

Done when: readiness actually drops the tier on a bad sleep day

- [ ] HealthKit permissions + read sleep / HRV / restingHR / mindful / menstrualFlow
- [ ] energy / readiness calculation + 28-day rolling median baseline + tests
- [ ] Tier thresholds and random composition table, 1.3x effort multiplier at low tier
- [ ] Cycle detection: tier capped at normal, excludes `intensity = high`
- [ ] EventKit reads calendar, `calendar_workout:30` auto-verification
- [ ] `mindfulSession` auto-verification (allows multiple sessions per day to accumulate)

## Stage 4 — Monthly calendar page

Done when: any past day can be reviewed

- [ ] Month view: green dot (random quests completed), blue dot (routines fully done), star (hidden)
- [ ] Epic-completed week highlight, judged by `weekKey` (not row index)
- [ ] Custom `LazyVGrid` (not `UICalendarView`)
- [ ] Day detail sheet: quest/routine status, points, completion time, auto-verify/degraded markers, that day's redemptions and penalties, `DailyContext`

## Stage 5 — Epic, paid reroll, redemption

- [ ] Epic generation (every Monday, visible immediately), extension (max twice)
- [ ] Reroll pricing: 1.5x escalation, rounded up + tests; epic reroll fixed at 80/week
- [ ] `Reward.estimatedCost` → coins conversion formula + tests
- [ ] Redemption page UI, reroll disabled while balance is negative
- [ ] Virtual item redemption (cancel a quest, epic extension, streak freeze)
- [ ] Quest library management UI + affinity feedback

## Stage 6 — Backup and migration

Done when: balance matches exactly

- [ ] Upgrade the minimal export from Stage 1 to real `fileExporter` to iCloud Drive, dated filename, includes `schemaVersion`
- [ ] JSON import + confirm before overwrite
- [ ] One-time importer for the web prototype's save data

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
