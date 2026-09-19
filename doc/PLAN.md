# Life RPG — iOS App Plan

A personal life RPG app, single-user, not published, no onboarding, no social features.

Every day the app issues a handful of random quests plus routines due that day; clearing all of them unlocks one light "hidden" bonus quest, and there's also one epic per week. Completing a quest rolls points within a difficulty-band range; overdue routines lose escalating points for up to three days, and can be made up late for half credit. Points are spent on real-world rewards, virtual items, and rerolls. Data lives on-device, can be exported to iCloud Drive, and history can be reviewed via a monthly calendar page.

Seed data lives in `side_quests.csv` and `routine_quests.csv`.

---

## 1. Tech stack and account prerequisites

| Item | Choice |
|---|---|
| UI | SwiftUI, iOS 17+ |
| Local storage | SwiftData (SQLite under the hood, inside the app sandbox) |
| Health data | HealthKit: sleep, HRV, resting HR, mindful sessions, menstrualFlow |
| Workout logging | EventKit reading Calendar (a Shortcut writes Apple Fitness workouts into the calendar) |
| Oura readiness | Oura API v2, integrated later |
| Cloud | Manual JSON export to iCloud Drive for now; CloudKit deferred until after paying for a developer account |

A free Apple ID can install from Xcode onto your own device; the signature expires after 7 days, just re-run Xcode (overwrite install, data preserved). **No paid account for now.** CloudKit and push notifications need a paid account; HealthKit generally works under a free personal team, but before starting Stage 3, create an empty project with HealthKit enabled to verify it installs, to avoid rework later.

CloudKit-ready constraints are followed from day one: every `@Model` property gets a default or is optional, no `@Attribute(.unique)`, all relationships optional.

---

## 2. Difficulty standard: resistance, not exertion

Difficulty tiers are graded by **psychological resistance**, not time or physical effort. "Message a friend you haven't talked to in a long time" is H, "walk by the river" is M — this is intentional, because what needs pushing is exactly the high-resistance stuff. The physical-exertion dimension is carried separately by the `intensity` field, used only for filtering down at low energy.

| Tier | Points | Notes |
|---|---|---|
| T (trivial) | 4 each, a set of three = 12 total | Micro-actions; three are bundled into one slot, all must be done to count as complete |
| E | 5–15 | |
| M | 12–30 | |
| H | 25–50 | |
| EPIC | 60–150 | One per week, can be extended or rerolled |

The T tier exists to give micro-habits like "floss" or "apply hand cream" somewhere to live, without diluting the E pool. Giving them their own slot would make the payoff feel too thin — so when a T group appears, it **takes the place of one E slot** (three T items = one slot, scored as 12 as a whole).

**Hidden is a flag on the template, not a difficulty tier.** Any quest that's light and fun can be `hidden_eligible = true`; when drawing the hidden slot, only that pool is sampled, and points are calculated from the quest's own difficulty plus a flat +10 bonus (the bonus is not affected by the low-tier multiplier, see §5). So "visit a coffee shop you've never been to" can show up either as a regular M quest or as the hidden one. Hidden is meant as a light reward after full-clear, not a hard challenge.

---

## 3. Daily structure

### Random slot count is driven dynamically by routine load

Routines already cover the genuinely hard tasks — working on a project, studying, sending job applications, exercising — so the random pool leans light and self-care. If the random count were fixed at three per day, Saturday (5 routines) would stack up to ten tasks and just cause burnout/abandonment.

```
randomSlots = clamp(4 - ceil(dueRoutineCount / 2), 1, 3)
```

Friday with 1 routine gets 3 random quests; Wednesday with 3 gets 2; Saturday with 5 gets only 1.

`dueRoutineCount` counts every **active** routine due that day (including `counts_for_clear = false` ones); inactive routines don't count.

### Hidden unlock

Unlocks once all `counts_for_clear` routines and all random slots for the day are completed. On heavy-load days there are more routines but fewer random quests, which actually makes unlocking easier — a bit of compensation for a hard day.

### Epic

Generated every Monday, valid through Sunday, visible from the start, doesn't count toward full-clear, and isn't penalized if skipped. Can be extended a week by spending coins (max twice) or rerolled.

### Ad-hoc routine replacing a random quest

A routine can be manually added for the day, but must specify which random slot it replaces. The replaced random quest is marked `replaced` and doesn't count toward full-clear. The replacement is free, but the cost is that this routine now loses points if not done.

### Cooldown

Cooldown counts from the **completion** day, not the draw day: after completing a quest it isn't eligible again for its cooldown period — T and E are 3 days, M is 7 days, H is 14 days; individual entries can override this in the CSV.

A quest that was drawn but not completed (including one rerolled away) gets a short 1-day cooldown, so it doesn't show up again the very next day.

"Cooldown N days" means: last key on day D → ineligible on D+1 … D+N, eligible again from D+N+1. A template is eligible only when both checks pass (`lastCompletedDayKey` vs its own cooldown, `lastServedDayKey` vs 1 day).

### Weekend-only quests

Big things that only fit on a weekend (video call with parents, meeting friends, day trips, hikes, decluttering) are marked `weekend_only = TRUE`; on Mon–Fri they're excluded from the pool. The parents video call used to be a biweekly routine; it's now a weekend-only H quest with a 14-day cooldown, so it comes up roughly every other weekend.

### Streak

Streak = number of consecutive days with **at least one random quest completed** (regular slots, the T group, and hidden all count; routines and epic don't). A streak freeze covers one missed day without breaking it.

### Parameterized templates

Entries with bracketed placeholders (a color, learning about something, a journal prompt) substitute in a random value from a `variants` array — one entry does the work of ten.

---

## 4. Routine mechanics

### Frequency types

| kind | spec example | use |
|---|---|---|
| weekly | `MON,THU` | fixed weekdays |
| everyNDays | `3` | computed from last completion date |
| monthly | `15` | a specific day of the month |
| nthWeekdayOfMonth | `1:SAT` / `-1:SAT` | first / last Saturday of the month |
| everyNWeeksOnWeekday | `2:SAT` | biweekly Saturday, needs a starting-week anchor (`anchorWeekKey`); no routine uses it right now |

### Movable within the week (flexible_within_week)

When Saturday's weight training gets broken by social plans, it's allowed to shift to any day that week — the check changes from "was it done today" to "has the weekly count hit `weekly_target`," settled on Sunday to determine any shortfall. Exercise, project work, job applications, and studying all have this on; taking out the trash and cleaning the litter box must be done same-day, so it's off.

### Degradable (degraded_text)

On low-energy days, routines aren't penalized for being skipped — instead they're automatically swapped for a degraded version: running becomes an incline walk, weight training becomes light dumbbells or bodyweight work, and completing it still awards full points. This has to be encoded in the app, not left to willpower in the moment, because the goal is to lower intensity, not skip entirely.

**Only routines with a non-empty `degraded_text` can degrade**; routines without one stay as-is regardless of tier.

### Overdue penalty

Applies to **routines only**. Random quests refresh daily — an uncompleted random quest just earns nothing, no penalty.

Overdue routines don't disappear — they stay pinned at the top of the today page, marked with days overdue. Penalties **escalate and stack**: each day that ends with the routine still undone deducts a separate penalty.

| Day (1 = due day) | Deducted at end of that day if still undone | Example, base 50 |
|---|---|---|
| 1 | 50% of base | −25 |
| 2 | 75% of base | −38 (37.5 rounded) |
| 3 | 100% of base | −50 |
| 4 | auto-converted to `skipped` (`kind = "skip"`, 0 points), removed from the today page | 0 |

Worst case total = 225% of base (−113 in the example).

**Making up late**: completing on day 2 or 3 awards **half of base** (× the low-tier multiplier, rounded), and that day's deduction is not applied — deductions from earlier days stay. A made-up routine does **not** count toward that day's full-clear. Completing on the due day is just a normal completion.

```
overduePenalty(day) = round(basePoints × [0.5, 0.75, 1.0][day - 1])   // day 1...3
lateCompletion      = round(basePoints × 0.5 × m)                       // m = low-tier multiplier (§5)
```

There is no daily penalty cap.

Actively skipping is recorded separately as a `kind = "skip"` ledger entry with 0 points, so the calendar page can distinguish "actually did it" from "gave up."

### Non-scoring routines

"Go to the office" is set to `counts_for_clear = false`, 5 points; it doesn't count toward full-clear and isn't penalized. Not going has real-world consequences on its own, so the existing constraint is enough — scoring it further would just inflate the score on commute days.

**Currently disabled** (`is_active = FALSE` in the CSV), so it doesn't take up routine load on Mon/Thu either.

---

## 5. Energy score and difficulty adjustment

Baseline is the rolling median over the past 28 days. On first launch, do a one-time backfill from HealthKit history instead of waiting a month.

```swift
// each ratio clamped to [0.6, 1.4] so a single outlier can't dominate
E = 0.45 × (hrv / hrvMedian)
  + 0.35 × (sleepHours / sleepMedian)
  + 0.20 × (rhrMedian / restingHR)      // RHR is an inverse indicator, numerator/denominator swapped

readiness = clamp(round(E × 75), 35, 100)
```

Thresholds: E < 0.85 very low, 0.85–0.92 low, 0.92–1.06 normal, > 1.06 high.

| Tier | Random composition (at 3 slots) |
|---|---|
| Very low | 3 E's, one of which is guaranteed to be the T group |
| Low | 2 E + 1 M |
| Normal | E + M + H |
| High | 2 M + 1 H |

On low-tier days (`low` and `veryLow`), points get a 1.3x effort multiplier. Moving is harder when you're in bad shape than good shape, so the payout shouldn't collapse along with it.

```
m = (tier == .low || tier == .veryLow) ? 1.3 : 1.0
questPoints   = round(roll(difficulty) × m) + (isHidden ? 10 : 0)   // hidden +10 is NOT multiplied
tGroupPoints  = round(12 × m)                                       // whole group, not per item
routinePoints = round(basePoints × m)                               // routines (incl. degraded) also get it
```

All rounding is round-half-up (`.toNearestOrAwayFromZero`), same as the penalty.

Readiness uses the proxy above for phase one; once the Oura API v2 (`/v2/usercollection/daily_readiness`, personal access token stored in Keychain) is integrated, it replaces the data source but the formula stays the same. Oura's sleep/HR/HRV data flows into HealthKit automatically as long as write access is enabled in its own app, but readiness is Oura's own composite metric and does not flow into HealthKit.

### Menstrual cycle

Determined by a HealthKit `menstrualFlow` entry that day. On cycle days, the tier is capped at normal and `intensity = high` templates are excluded — but it's not forced down to low, since being on a cycle doesn't mean being weak.

### Auto-verification

On the Calendar side, events written by the Shortcut are read, and anything past a duration threshold auto-verifies (`calendar_workout:30`). iOS 17+ needs Full Access to Calendar. Meditation goes through HealthKit's `mindfulSession`, allowing multiple sessions to accumulate in a day. Auto-verified quests are marked `sourceType = .healthKit` and need no manual tap.

Reading has no app that writes to HealthKit, so it can only go through FamilyControls + DeviceActivity (needs a separate entitlement, and the data is an opaque token usable only for threshold checks) — this is scheduled last; manual check-in for now.

---

## 6. Economy system

### Income estimate

Median E is 10, M is 21, H is 37, the T group is 12, hidden is around 30, routines are 10–80 depending on that day's load. Full daily clear averages 120–160, epic averages about 15/day spread out. An ideal week is around 1000; at a realistic 75% completion rate, it settles around 750–800/week.

### Reward pricing auto-converted from estimated spend

`Reward` stores `estimatedCost` (real currency); coins are computed from a formula to avoid manual entries getting inconsistent:

```
coins = cost <= 500 ? cost × 10 : 5000 + (cost - 500) × 5
```

The multiplier is a single global parameter — if the pacing feels off after a month, change one number and every reward price recalculates; past redemption records are unaffected.

| Reward | Estimated cost | Coins | Roughly time to save up |
|---|---|---|---|
| A nice meal | 100 | 1000 | just over a week |
| Going out for drinks | 100 | 1000 | just over a week |
| A Michelin meal | 750 | 6250 | eight weeks |
| Wishlist headphones | 600 | 5500 | seven weeks |
| A short trip | 500–1000 | 5000–7500 | six to nine weeks |
| New furniture | 2000 | 12500 | four months |

### Virtual rewards

Pricing must be noticeably higher than the payout from completing the underlying quest, or it becomes an arbitrage.

| Item | Coins |
|---|---|
| Cancel an E | 120 |
| Cancel an M | 250 |
| Cancel an H | 450 |
| Cancel a routine | 200 |
| Extend epic by a week | 400 |
| Streak freeze | 300 |

### Reroll

Escalates by 1.5x, rounded up, resets daily. Base is E 10, M 20, H 30 — so E goes 10 / 15 / 23 / 34, H goes 30 / 45 / 68 / 102. Epic reroll is a flat 80, once per week.

### Balance can go negative

If routine penalties push the balance below zero, let it stay negative and display it in red — more honest than clamping to zero. Redemption still requires sufficient balance though, or going into debt to buy headphones would defeat the point. While in debt, reroll is unavailable — quests need to be completed first to bring the balance back up.

### Level

Balance always equals the sum of the ledger, never stored separately; cumulative points only sum positive entries; `level = floor(sqrt(total / 60)) + 1`.

---

## 7. Data model

```swift
enum Difficulty: String, Codable, CaseIterable {
    case trivial, easy, medium, hard, epic
    var range: ClosedRange<Int> {
        switch self {
        case .trivial: 4...4
        case .easy:    5...15
        case .medium:  12...30
        case .hard:    25...50
        case .epic:    60...150
        }
    }
    var rerollBase: Int {
        switch self {
        case .trivial: 5; case .easy: 10; case .medium: 20
        case .hard: 30;  case .epic: 80
        }
    }
    var cooldownDays: Int {
        switch self {
        case .trivial, .easy: 3; case .medium: 7; case .hard: 14; case .epic: 0
        }
    }
}

enum Intensity: String, Codable { case low, medium, high }
enum Tier: String, Codable { case veryLow, low, normal, high }
enum RecurrenceKind: String, Codable {
    case weekly, everyNDays, monthly, nthWeekdayOfMonth, everyNWeeksOnWeekday
}

@Model final class QuestTemplate {
    var id: UUID = UUID()
    var text: String = ""
    var difficultyRaw: String = Difficulty.easy.rawValue
    var intensityRaw: String = Intensity.low.rawValue
    var hiddenEligible: Bool = false
    var weekendOnly: Bool = false          // excluded from the pool Mon–Fri
    var cooldownDaysOverride: Int?
    var variants: [String] = []            // parameterized placeholders
    var launchURLString: String?
    var autoVerifyRule: String?            // "mindful:15" / "calendar_workout:30"
    var affinity: Int = 0                  // -2...2, sampling weight
    var lastServedDayKey: String?          // drawn but not completed → 1-day cooldown
    var lastCompletedDayKey: String?       // completed → full cooldown
    var isActive: Bool = true
}

@Model final class RoutineTask {
    var id: UUID = UUID()
    var text: String = ""
    var basePoints: Int = 15
    var difficultyRaw: String = Difficulty.easy.rawValue
    var intensityRaw: String = Intensity.low.rawValue
    var kindRaw: String = RecurrenceKind.weekly.rawValue
    var spec: String = ""                  // "MON,THU" / "3" / "1:SAT" / "2:SAT"
    var anchorWeekKey: String?             // everyNWeeksOnWeekday only: a week the routine is due, e.g. "2026-W38"
    var weeklyTarget: Int = 1
    var flexibleWithinWeek: Bool = false
    var countsForClear: Bool = true
    var degradedText: String?
    var launchURLString: String?
    var autoVerifyRule: String?
    var lastCompletedDayKey: String?
    var isActive: Bool = true
}

@Model final class DailyQuest {            // today's instance of a random slot
    var id: UUID = UUID()
    var dayKey: String = ""                // "2026-09-17", local timezone
    var weekKey: String = ""               // "2026-W38", used for epic and flexible settlement
    var slotRaw: String = ""
    var isHiddenSlot: Bool = false
    var templateID: UUID?
    var textSnapshot: String = ""          // snapshot; template edits/deletes don't affect history
    var launchURLSnapshot: String?
    var trivialGroup: [String] = []        // the three texts in the T group; non-empty = isTrivialGroup
    var trivialDone: [Bool] = []
    var points: Int?                       // nil = not completed
    var completedAt: Date?
    var sourceTypeRaw: String = "manual"
    var rerollCount: Int = 0
    var replaced: Bool = false             // bumped by an ad-hoc routine
    var extensionCount: Int = 0            // epic only, max 2
}

@Model final class RoutineOccurrence {
    var id: UUID = UUID()
    var routineID: UUID?
    var dueDayKey: String = ""
    var weekKey: String = ""
    var completedDayKey: String?
    var textSnapshot: String = ""
    var usedDegraded: Bool = false
    var basePoints: Int = 0
    var awardedPoints: Int?                // late make-up = half of base × m
    var penaltyApplied: Int = 0            // running total of escalating deductions
    var skipped: Bool = false              // user skip, or auto on day 4
    var completedAt: Date?
}

@Model final class Reward {
    var id: UUID = UUID()
    var name: String = ""
    var estimatedCost: Double = 0          // real currency, 0 means a virtual item
    var virtualKind: String?               // "cancel_hard" / "extend_epic" / "streak_freeze"
    var fixedCoins: Int?                   // virtual items are priced directly
    var isActive: Bool = true
}

@Model final class LedgerEntry {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var dayKey: String = ""
    var kind: String = "quest"   // quest / routine / redeem / reroll / penalty / skip / adjust
    var points: Int = 0          // spending and penalties are negative
    var refID: UUID?
    var note: String = ""
}

@Model final class DailyContext {
    var dayKey: String = ""
    var hrv: Double?
    var sleepHours: Double?
    var restingHR: Double?
    var energy: Double = 1.0
    var readiness: Int = 75
    var tierRaw: String = Tier.normal.rawValue
    var onCycle: Bool = false
    var routineLoad: Int = 0
    var randomSlots: Int = 3
}
```

Design notes: enums are stored as raw Strings, since `#Predicate` filters most reliably on raw values (the CSV uses `T/E/M/H/EPIC`, the importer maps these to the rawValues); `dayKey` is a string to sidestep timezone and startOfDay pitfalls; quest text is snapshotted so soft-deleting a template doesn't affect history; `DailyContext` lets the calendar page show body state and that day's difficulty side by side.

---

## 8. Core logic sample

```swift
// Fixed calendars: never Calendar.current, whose firstWeekday / calendar system
// depend on the user's region settings and would shift week boundaries.
let gregorian: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c }()
let iso8601: Calendar  = { var c = Calendar(identifier: .iso8601);   c.timeZone = .current; return c }()

extension Date {
    var dayKey: String {                    // "2026-09-17"
        let c = gregorian.dateComponents([.year, .month, .day], from: self)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    var weekKey: String {                   // "2026-W38", Monday-start ISO week
        let c = iso8601.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear!, c.weekOfYear!)
    }
}

@MainActor
func ensureToday(_ ctx: ModelContext, now: Date = Date(),
                 rng: inout some RandomNumberGenerator) throws {
    let today = now.dayKey                  // take the key ONCE; everything below uses it

    // Catch-up: settle every day since the last processed one (app may not have
    // been opened for days) — escalating overdue penalties, day-4 auto-skip,
    // Sunday flexible settlement.
    for key in dayKeys(after: lastProcessedDayKey(ctx), upTo: today) {
        try settleDay(key, ctx)
    }

    // Idempotency keyed on DailyContext, not DailyQuest: if every sample() came
    // back nil there'd be no DailyQuest and we'd regenerate occurrences again.
    guard try ctx.fetch(FetchDescriptor<DailyContext>(
        predicate: #Predicate { $0.dayKey == today })).isEmpty else { return }

    let day = try syncHealthContext(for: today, ctx)   // energy / readiness / tier / cycle
    let due = try dueRoutines(on: today, ctx)          // active only; generates RoutineOccurrence
    let slots = max(1, min(3, 4 - Int(ceil(Double(due.count) / 2))))
    day.routineLoad = due.count
    day.randomSlots = slots

    for d in composition(tier: day.tier, slots: slots, rng: &rng) {   // may yield a T group in an E slot
        if let t = sample(difficulty: d, context: day, ctx, rng: &rng) {
            t.lastServedDayKey = today
            ctx.insert(DailyQuest(dayKey: today, template: t))
        }
    }
    try ctx.save()
}

// Cooldown: completed → full cooldown from completion day; drawn-but-not-done → 1 day.
func inCooldown(_ t: QuestTemplate, today: String) -> Bool {
    let full = t.cooldownDaysOverride ?? t.difficulty.cooldownDays
    if let done = t.lastCompletedDayKey, daysBetween(done, today) <= full { return true }
    if let served = t.lastServedDayKey, daysBetween(served, today) <= 1 { return true }
    return false
}

// Sampling: excludes items on cooldown, weighted by affinity — disliked items are downweighted but never disappear
func sample(difficulty: Difficulty, context c: DailyContext, _ ctx: ModelContext,
            rng: inout some RandomNumberGenerator) -> QuestTemplate? {
    let pool = (try? ctx.fetch(FetchDescriptor<QuestTemplate>(
        predicate: #Predicate { $0.isActive })))?
        .filter { $0.difficulty == difficulty }
        .filter { allowedIntensity(c).contains($0.intensity) }
        .filter { !$0.weekendOnly || isWeekend(c.dayKey) }
        .filter { !inCooldown($0, today: c.dayKey) } ?? []
    let weighted = pool.flatMap { t in
        Array(repeating: t, count: max(1, 3 + t.affinity))   // affinity -2 → 1, +2 → 5
    }
    return weighted.randomElement(using: &rng)
}

func effortMultiplier(_ tier: Tier) -> Double {
    tier == .low || tier == .veryLow ? 1.3 : 1.0
}

func awardedPoints(_ q: DailyQuest, tier: Tier, rng: inout some RandomNumberGenerator) -> Int {
    let m = effortMultiplier(tier)
    let base = q.isTrivialGroup ? 12 : Int.random(in: q.slot.range, using: &rng)
    let p = Int((Double(base) * m).rounded())                // round half away from zero
    return p + (q.isHiddenSlot ? 10 : 0)                     // hidden bonus is not multiplied
}

func routinePoints(_ o: RoutineOccurrence, tier: Tier) -> Int {
    Int((Double(o.basePoints) * effortMultiplier(tier)).rounded())
}

// Deducted at the end of each overdue day still undone; day 4 → skipped instead
func overduePenalty(_ o: RoutineOccurrence, day: Int) -> Int {     // day 1...3, 1 = due day
    let rate = [0.5, 0.75, 1.0][day - 1]
    return Int((Double(o.basePoints) * rate).rounded())
}

func lateCompletionPoints(_ o: RoutineOccurrence, tier: Tier) -> Int {
    Int((Double(o.basePoints) * 0.5 * effortMultiplier(tier)).rounded())
}

func rerollCost(_ q: DailyQuest) -> Int {
    Int((Double(q.slot.rerollBase) * pow(1.5, Double(q.rerollCount))).rounded(.up))
}
```

`ensureToday` is hooked to `scenePhase` becoming `.active`, so it refreshes even if the app crosses midnight while backgrounded and is then brought back to the foreground. `now` and `rng` are injected so tests can fix the date and use a seeded generator.

---

## 9. Monthly calendar page

A green dot shows how many random quests were completed that day (zero to three dots), a blue dot shows whether all routines were completed, a star shows hidden-quest completion, and the whole row for a week where the epic was completed gets a highlighted background.

Implementation note: a week can span two months, so the epic highlight is judged by `weekKey`, not by row index. Use a custom `LazyVGrid`, not `UICalendarView`.

The day detail sheet shows all of that day's random slots and routines with status, points, completion time, whether it was auto-verified or completed in degraded form, that day's redemptions/rerolls/penalties, and the `DailyContext` values for HRV, sleep, readiness, and tier.

No week view for now. A stats page can wait until there's been actual usage over time.

---

## 10. Backup and versioning

Export the whole DB as JSON via `fileExporter` to iCloud Drive, filename dated; confirm before overwriting on import.

The JSON carries its own integer `schemaVersion`, incremented only on model changes, decoupled from the GitHub release tag (things like v0.1). Tags will jump ahead due to UI changes, so import only looks at schemaVersion.

The web prototype's save file is base64 JSON, with timestamps, quest text, points, and difficulty in the log — enough to reconstruct history. Build a one-time importer to migrate it over, then retire the web version.

---

## 11. Stage breakdown

| Stage | Content | Done when |
|---|---|---|
| 0 | project, model, seed from the two CSVs | DB has data, app runs |
| 1 | Today page, random slot generation, completion rolls, undo, ledger, HUD | Ready for daily use |
| 2 | Routine layer: frequency parsing, overdue, degrade, movable-within-week, ad-hoc replacement | Saturday no longer stacks up to ten tasks |
| 3 | HealthKit and Calendar: energy, readiness proxy, tier adjustment, auto-verification, cycle | Tier actually drops on a bad sleep night |
| 4 | Monthly calendar page and day detail | Any day can be reviewed |
| 5 | Epic, paid reroll, redemption page (including estimatedCost conversion), quest library management and affinity feedback | |
| 6 | JSON export/import, web version migration | Balance matches exactly |
| 7 | Optional: Oura API, DeviceActivity, notifications, widget, CloudKit (requires paying) | |

HealthKit is pulled ahead of the calendar page because it changes slot-generation logic and fields — doing it early saves rework.

Acceptance per stage: quests refresh correctly across midnight; manually change system time to test streak, reroll reset, and flexible routine weekly settlement; export JSON, reinstall, and confirm a complete import.

---

## 12. Open questions

The exact `weekly_target` number for exercise routines — weight training is currently written as 2, but the actual frequency after social plans break it needs a week or two of real testing.

Probability of the T group appearing — currently envisioned as guaranteed at very-low energy, 40% otherwise (only when the composition has an E slot for it to take); tune after use.

Flexible routines and the escalating penalty: the Sunday shortfall has no "next day" within the week — does it escalate into Mon/Tue of the following week, or is it a single deduction on Sunday?

Weekend H exposure: Saturday's routine load leaves only 1 random slot (Sunday 2), so weekend-only H quests may rarely get drawn. Consider guaranteeing an H slot on weekends, or computing weekend slots differently.

Affinity feedback needs a week or two to accumulate before batch-expanding the quest library. The side quest H pool currently has only nine entries, a bit thin, but leaving it for now until it's clearer which category is actually worth doing.
