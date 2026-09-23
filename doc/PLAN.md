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

Difficulty tiers are graded by **psychological resistance**, not time or physical effort. "Message a friend you haven't talked to in a long time" is H, "walk by the river" is M — this is intentional, because what needs pushing is exactly the high-resistance stuff.

There is **one** difficulty axis and no second one. An earlier draft carried a separate `intensity` (low/medium/high) for physical exertion, used only to filter the pool down at low energy — but the composition table below already does that by dropping the hard slots, and for routines nothing ever read it. Two metrics for "how hard" is how they drift apart, so `intensity` was removed (`SchemaV2`).

| Tier | Points | Notes |
|---|---|---|
| T (trivial) | 4 each, a set of three = 12 total | Micro-actions; three are bundled into one slot, all must be done to count as complete |
| E | 5–15 | |
| M | 12–30 | |
| H | 25–50 | |
| EPIC | 60–150 | One per week, can be extended or rerolled |

The T tier exists to give micro-habits like "floss" or "apply hand cream" somewhere to live, without diluting the E pool. Three of them make one slot, scored as 12 as a whole, so the payoff isn't thin.

**T is simply the rung below E**, and it sits in the composition table like any other difficulty — it does not "replace" an E slot, which would have been a second mechanism for something the one difficulty axis already says. It therefore appears exactly on the days the table puts it on: `low` and `veryLow`. That is what the T tier is for — on a day you can barely function, the win available is flossing.

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

Unlocks once all `counts_for_clear` routines and all random slots for the day are completed. Flexible routines due that day count too: moving one to a later day avoids a penalty, but it costs that day's hidden quest. On heavy-load days there are more routines but fewer random quests, which actually makes unlocking easier — a bit of compensation for a hard day.

### Epic

Generated every Monday, valid through Sunday, visible from the start, doesn't count toward full-clear, and isn't penalized if skipped. Can be extended a week by spending coins (max twice) or rerolled.

### Ad-hoc routine replacing a random quest

A routine can be manually added for the day, but must specify which random slot it replaces. The replaced random quest is marked `replaced` and doesn't count toward full-clear. The replacement is free, but the cost is that this routine now loses points if not done.

- **Source**, on its own page with two tabs: picked from the routine library (active routines with nothing already on today's page — not due today, not added, not still open from an earlier day), or written on the spot with a difficulty. A custom task's base is the midpoint of that difficulty's range: E 10, M 21, H 38. T and EPIC can't be chosen.
- **Which slot**: any random slot of today that is not done, not hidden and not already replaced. Final, like completion.
- **Independent of the library**: the ad-hoc occurrence carries no `routineID`, so it is never flexible, never counts toward a weekly target and never moves the routine's next due date. It is always on the fixed overdue ladder and always gates the full-clear — even when picked from a `counts_for_clear = false` routine, which would otherwise make it a free pass out of a hard slot.

### Cooldown

Cooldown counts from the **completion** day, not the draw day: after completing a quest it isn't eligible again for its cooldown period — T and E are 3 days, M is 7 days, H is 14 days; individual entries can override this in the CSV.

A quest that was drawn but not completed (including one rerolled away) gets a short 1-day cooldown, so it doesn't show up again the very next day.

"Cooldown N days" means: last key on day D → ineligible on D+1 … D+N, eligible again from D+N+1. A template is eligible only when both checks pass (`lastCompletedDayKey` vs its own cooldown, `lastServedDayKey` vs 1 day).

### Weekend-only quests

Big things that only fit on a weekend (video call with parents, meeting friends, day trips, hikes, decluttering) are marked `weekend_only = TRUE`; on Mon–Fri they're excluded from the pool. The parents video call used to be a biweekly routine; it's now a weekend-only H quest with a 14-day cooldown, so it comes up roughly every other weekend.

### Streak

Streak = number of consecutive days with **at least one random quest completed** (regular slots, the T group, and hidden all count; routines and epic don't). A streak freeze covers one missed day without breaking it.

### Completion is final

There is no undo on the today page. A completed quest writes its ledger entry and starts the
template's cooldown, and neither is reversed: a reversible checkbox would turn the points roll into
something you can re-roll until the number is good. A genuine mistake is corrected with an `adjust`
ledger entry, which stays visible in the history. Every completion tap is therefore confirmed once.

### Parameterized templates

Entries phrased as an open prompt (a color, learning about something, a journal prompt) draw a random value from a `variants` array — one entry does the work of ten.

The value is drawn once, when the day is generated, and snapshotted onto the `DailyQuest` as `variantSnapshot` **beside** the text rather than spliced into it. The CSV wording stays the row's identity — which is what the seed merge keys on, and what makes a year of history still greppable — and the page shows the variant underneath it as the actual ask of the day.

---

## 4. Routine mechanics

### Frequency types

| kind | spec example | use |
|---|---|---|
| weekly | `MON,THU` | fixed weekdays |
| everyNDays | `3` | computed from last completion date; never completed = due at once; a skipped round restarts the count from the skip day |
| monthly | `15` | a specific day of the month |
| nthWeekdayOfMonth | `1:SAT` / `-1:SAT` | first / last Saturday of the month; n is 1…4 or -1 (`5:SAT` is rejected — most months have no fifth) |
| everyNWeeksOnWeekday | `2:SAT` | biweekly Saturday; `anchorWeekKey` is set by the first completion, due every week until then; no routine uses it right now |

### Movable within the week (flexible_within_week)

When Saturday's weight training gets broken by social plans, it's allowed to shift to any day that week — the check changes from "was it done today" to "has the weekly count hit `weekly_target`," settled on Sunday to determine any shortfall. Once the week's target is met (ahead completions included), its remaining scheduled days that week don't generate it at all. Exercise, project work, job applications, and studying all have this on; taking out the trash and cleaning the litter box must be done same-day, so it's off.

### Downgrade versions

On low-energy days, routines aren't penalized for being skipped — instead they're automatically swapped for a lighter version: running becomes an incline walk, strength training becomes a walk. This has to be encoded in the app, not left to willpower in the moment, because the goal is to lower the effort, not skip entirely.

**A downgrade version is a routine row of its own**, listed on its parent as `downgradeIDs` (the seed CSV says `downgrade_of`, naming the parents by text, `|`-separated). It therefore carries its own text, its own `base_points` and its own `auto_verify` rule — a 30-minute walk verifies as a 30-minute walk, not against the 40-minute rule of the session it replaced. It is never scheduled on its own; it is only ever reached through the routine that offers it. Routines with no downgrade version stay as-is regardless of tier.

- **Low day** = tier `low` or `veryLow` — the same rule as the 1.3× multiplier (`Tier.isLow`), and what the first three cycle days produce.
- **Decided when the day is generated**: the occurrence starts out as the light version, and with several on offer one is drawn at random. An overdue one carried from an earlier day keeps the version it was created with; a flexible routine done ahead on a low day asks which version was done.
- **The light version pays its own points.** A walk pays what a walk is worth, not what the session would have — otherwise the row's `base_points` would be data nothing reads. The overdue penalty follows the same number: a missed walk costs what a walk is worth.
- **The original can still be chosen**, for the original's points, until the occurrence is done or skipped. `usedDegraded` records which version was actually done. The original wording stays in `textSnapshot`, the light one sits beside it.
- **Ad-hoc routines never degrade** — they are picked on purpose, on the spot.

A strength routine's downgrade versions are all deliberately *other kinds of thing* (a walk), never lighter weights. That is what makes the cycle rule below mean what it says.

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
| Very low | T + 2 E |
| Low | T + E + M |
| Normal | E + M + H |
| High | 2 M + 1 H |

The table is written easy → hard, and a day with fewer than 3 slots **drops from the hard end**:
at `normal`, 2 slots are E + M and 1 slot is an E; a heavy routine day at `low` keeps the T group
as its single slot. No H is guaranteed on a weekend — see §12. Nothing in the composition is
random: the tier alone decides the day's shape.

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

Determined by HealthKit `menstrualFlow` entries. Two weeks of them are read rather than just today's, because what matters is **which day of the round** today is: the count runs in calendar days from the day the round started (`Cycle.day`), so a day that was never logged in the middle still counts, and a gap of more than a day starts a new round. A round that stops being logged stops counting after its third day.

- **Days 1–3 are held down to tier `low`** (`Energy.cap`). That single line is the whole rule: a low day already means fewer and easier random slots, the 1.3× effort multiplier, and every routine that offers one swapped for its downgrade version — so there is no strength training on day 1, there is a walk. A measured `veryLow` stays `veryLow`; the cap never pushes a tier up.
- **Day 4 onwards** is capped at normal, as before — being on a period is not the same as being weak.

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

**A reroll records what it swapped away.** Escalation has to accumulate on the day's slot, which is tempting to implement by overwriting the `DailyQuest` row in place — but that row *is* the history the calendar and the summary read, so overwriting it erases what was rerolled away. Instead the old row is kept and marked `rerolledAway`, and the replacement carries `rerollCount + 1`. Rerolled-away rows are skipped by full-clear and streak the same way `replaced` ones are. Escalation still resets daily, because a new day means new rows starting at zero.

**A reroll can never take the balance below zero.** Spending down to exactly zero is fine — that is not debt. Penalties are the only thing allowed to push the balance negative, because they are something that happens to you; a purchase you chose to make is not. Combined with the rule below, that gives two separate refusals: "clear the debt first" and "you can't afford it".

### Opening balance

A new store is granted 100 coins, once ever, as a `grant` ledger entry. Without it nothing can be spent for the first week, so nothing has a price and the first reroll is unreachable. The grant is keyed on a `grant` entry already existing rather than on the ledger being empty, so restoring a backup does not mint a second one.

### Balance can go negative

If routine penalties push the balance below zero, let it stay negative and display it in red — more honest than clamping to zero. Redemption still requires sufficient balance though, or going into debt to buy headphones would defeat the point. While in debt, reroll is unavailable — quests need to be completed first to bring the balance back up.

### Level

Balance always equals the sum of the ledger, never stored separately; `level = floor(sqrt(total / 60)) + 1`.

Cumulative points sum the positive entries **except the opening grant**. Spending must not drop the level, and a gift must not buy one: a level is a record of what has been done, so it counts what was earned, not what was held. A new store therefore opens at 100 coins and still reads level 1.

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

enum Tier: String, Codable { case veryLow, low, normal, high }
enum RecurrenceKind: String, Codable {
    case weekly, everyNDays, monthly, nthWeekdayOfMonth, everyNWeeksOnWeekday
}

@Model final class QuestTemplate {
    var id: UUID = UUID()
    var text: String = ""
    var difficultyRaw: String = Difficulty.easy.rawValue
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
    var kindRaw: String = RecurrenceKind.weekly.rawValue
    var spec: String = ""                  // "MON,THU" / "3" / "1:SAT" / "2:SAT"
    var anchorWeekKey: String?             // everyNWeeksOnWeekday only: a week the routine is due, e.g. "2026-W38"
    var weeklyTarget: Int = 1
    var flexibleWithinWeek: Bool = false
    var countsForClear: Bool = true
    var downgradeIDs: [UUID] = []          // lighter versions, themselves RoutineTask rows
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
    var variantSnapshot: String?           // the value drawn from a parameterized template
    var trivialGroup: [String] = []        // the three texts in the T group; non-empty = isTrivialGroup
    var trivialDone: [Bool] = []
    var trivialTemplateIDs: [UUID] = []    // parallel to trivialGroup, for the cooldown write-back
    var trivialVariants: [String] = []     // parallel to trivialGroup; "" = that item has none
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
    var degradedRoutineID: UUID?           // which downgrade version was drawn
    var degradedBasePoints: Int?           // its points; what the light version pays and is charged
    var countsForClear: Bool = true        // snapshot; false = recorded but doesn't gate full-clear
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
    var cycleDay: Int?                     // 1-based day of the period; 1–3 hold the tier at low
    var routineLoad: Int = 0
    var randomSlots: Int = 3
}

// Feedback is an append-only log, not a field on the template: the same quest can be rated
// differently in March and September, and both readings are kept. `QuestTemplate.affinity` stays
// the one value sampling reads; these tables are where it comes from and how it is explained.
@Model final class QuestRating {
    var id: UUID = UUID()
    var targetID: UUID?                    // QuestTemplate.id or RoutineTask.id
    var targetKindRaw: String = "quest"    // quest / routine
    var textSnapshot: String = ""
    var rating: Int = 0                    // -2...2, same scale as affinity
    var dayKey: String = ""
    var timestamp: Date = Date()
}

@Model final class QuestComment {
    var id: UUID = UUID()
    var targetID: UUID?
    var targetKindRaw: String = "quest"
    var textSnapshot: String = ""
    var comment: String = ""
    var dayKey: String = ""
    var timestamp: Date = Date()
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

    for d in composition(tier: day.tier, slots: slots) {              // a `.trivial` one is the T group
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

**Body data is read on every foreground, not only when the day is generated.** The day is generated the first time the app is opened that day, which can be before the watch has synced last night's sleep, or before a period was logged — so the tier it was locked to can simply be wrong. When a fresh reading disagrees, the app **asks** (`Replan.preview`), and only on confirmation re-plans the day (`Replan.apply`):

- **What is done is never touched.** Completed quests keep their text, their points and their ledger entry; an awarded value is never recomputed. Completed and skipped routines are left alone.
- Open slots are redrawn for the new tier's composition. A dropped one is marked `replaced` rather than deleted — the row stays as the record that it was once asked of you, and full-clear, streak and the calendar all skip `replaced` rows already.
- A slot the new composition asks for that a *finished* quest already answers is not drawn again.
- Open routines have their downgrade decision made again — a period logged at noon is exactly this case.
- A reading that did not actually come back never re-plans anything: denied HealthKit access returns the `normal` defaults, and those must not read as "your day got easier".

---

## 9. Monthly calendar page

A green dot shows how many random quests were completed that day (zero to three dots), a blue dot shows whether all routines were completed, a star shows hidden-quest completion, and the whole row for a week where the epic was completed gets a highlighted background.

Implementation note: a week can span two months, so the epic highlight is judged by `weekKey`, not by row index. Use a custom `LazyVGrid`, not `UICalendarView`.

The day detail sheet shows all of that day's random slots and routines with status, points, completion time, whether it was auto-verified or completed in degraded form, that day's redemptions/rerolls/penalties, and the `DailyContext` values for HRV, sleep, readiness, and tier.

No week view for now. A stats page can wait until there's been actual usage over time.

---

## 10. Backup and versioning

Export the whole DB as JSON via `fileExporter` to iCloud Drive, filename dated; confirm before overwriting on import.

What the JSON has to carry is exactly what the seed CSVs in `doc/` cannot rebuild: the history tables, and the `QuestRating` / `QuestComment` logs. Templates and routines are deliberately left out — they come back from the CSVs. There is a second, smaller export beside it that writes the two feedback logs out as CSV, because their destination is a spreadsheet or a diff against `doc/*.csv`, not an importer.

The JSON carries its own integer `schemaVersion`, incremented only on model changes, decoupled from the GitHub release tag (things like v0.1). Tags will jump ahead due to UI changes, so import only looks at schemaVersion.

The web prototype's save file is base64 JSON, with timestamps, quest text, points, and difficulty in the log — enough to reconstruct history. Build a one-time importer to migrate it over, then retire the web version.

---

## 11. Stage breakdown

| Stage | Content | Done when | Status |
|---|---|---|---|
| 0 | project, model, seed from the two CSVs | DB has data, app runs | **done** |
| 1 | Today page, random slot generation, completion rolls, payout reveal, ledger, HUD | Ready for daily use | **done, reviewed** |
| 2 | Routine layer: frequency scheduling, overdue, degrade, movable-within-week, ad-hoc replacement | Saturday no longer stacks up to ten tasks | parsing done, scheduling next |
| 3 | HealthKit and Calendar: energy, readiness proxy, tier adjustment, auto-verification, cycle | Tier actually drops on a bad sleep night | code done, device checks pending; extended with cycle days 1–3 and the foreground re-read |
| 4 | Monthly calendar page and day detail | Any day can be reviewed | code done, device check pending |
| 5 | Epic, paid reroll, redemption page (including estimatedCost conversion), quest library management and affinity feedback | Coins have somewhere to go | reroll pricing done |
| 6 | JSON export/import, web version migration | Balance matches exactly | export done, import pending |
| 7 | Optional: Oura API, DeviceActivity, notifications, widget, CloudKit (requires paying) | | |

HealthKit is pulled ahead of the calendar page because it changes slot-generation logic and fields — doing it early saves rework.

Two things were pulled forward out of their stage on the same argument, that **data which cannot be reconstructed must not start accumulating without a way off the device**: the JSON export (Stage 6) and the rating / comment log (Stage 5). Both record things the seed CSVs can never rebuild. `DEV_PLAN.md` tracks the detail.

Stage 1 is deliberately usable on its own but not yet *correct* on its own: `routineLoad` is 0 and `tier` is `normal` until Stages 2 and 3 fill them, so every day currently gets the full three random slots instead of the one or two a heavy routine day should have. That is the single biggest gap between the app as built and the app as designed.

Acceptance per stage: quests refresh correctly across midnight; manually change system time to test streak, reroll reset, and flexible routine weekly settlement; export JSON, reinstall, and confirm a complete import.

---

## 12. Open questions

The exact `weekly_target` number for exercise routines — weight training is currently written as 2, but the actual frequency after social plans break it needs a week or two of real testing.

~~Probability of the T group appearing~~ **Decided:** there is no probability. T is the bottom rung of the composition table (`low` and `veryLow` have one, `normal` and `high` have none), so the tier alone decides it — the same argument as merging `intensity` into difficulty: one mechanism, not two.

~~Whether the overdue penalty should still be scaled by readiness~~ **Decided (Stage 2):** it is not — fixed on base (base 50 → −25 / −38 / −50).

~~Flexible routines and the escalating penalty~~ **Decided (Stage 2):** a single deduction on Sunday, 50% of base per occurrence short of `weekly_target`; flexible routines have no daily ladder and nothing escalates into the next week.

~~Doing a flexible routine earlier than its due day~~ **Decided (Stage 2):** it is logged ahead against the next occurrence still to come that week, created on the spot and completed at full pay; that day then doesn't generate it again or count it as load.

~~Weekend H exposure~~ **Decided (Stage 1):** fewer slots drop from the hard end on every day of the week, weekends included, so no H is guaranteed and `weekend_only` H quests stay rare. Revisit once there is enough real data to say how rare; guaranteeing a weekend H slot would put the hardest random quest on the heaviest routine day, which is the opposite of what the dynamic slot count is for.

Affinity feedback needs a week or two to accumulate before batch-expanding the quest library. The side quest H pool currently has only nine entries, a bit thin, but leaving it for now until it's clearer which category is actually worth doing.

**How `affinity` is derived from the rating log.** Ratings are now collected (one tap, right after the payout reveal) and stored append-only with their dates, but nothing reads them back yet: `QuestTemplate.affinity` — the number sampling actually weights on — is still always 0. Newest rating wins? Mean over a trailing window? A window makes one bad day count for less, which is the point of rating repeatedly, but it also means a quest you have decisively gone off takes weeks to fade. Blocks the last task in Stage 5; harmless until then, because the log keeps everything either rule would need.

~~What the day detail shows about rerolls and ratings~~ **Decided (Stage 4):** both. Ratings hang on the completion that prompted them (`QuestRating.questID`); rerolled-away rows are shown too, so Stage 5's reroll must keep them marked `rerolledAway` — see §6.

~~Whether a reroll may push the balance negative~~ **Decided:** it may not. See §6, "Reroll".

~~Whether the opening grant counts toward the level~~ **Decided:** it does not. See §6, "Level".

~~How a parameterized template's variant reaches the page~~ **Decided (Stage 1):** drawn once at generation and snapshotted beside the text as `variantSnapshot`, never spliced into it. See §3, "Parameterized templates".
