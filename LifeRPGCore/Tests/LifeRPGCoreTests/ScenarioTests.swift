import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// Two weeks with the real seed, played day by day through `ensureToday`, the way the app runs
/// them: open the app, do some things, skip others, sleep through a few days.
///
/// Every number below was worked out by hand from `PLAN.md` §4 and the seed CSV, not computed by
/// the code under test. Random quests are generated but never completed, so the balance is
/// routines and penalties only (and no opening grant — nothing calls it here).
///
/// W39: Mon 2026-09-21 … Sun 27 (Sat 26 is the **last** Saturday → review bills).
/// W40: Mon 28 … Sun 2026-10-04 (Sat Oct 3 is the **first** Saturday → change bedsheets).
///
/// Seed bases: clean 25 · trash 5 (WED,SAT) · cat 15 · bedsheets 15 · grocery 10 · bills 20 ·
/// dumbbell 20 (×2) · running 25 · weights 30 (×2) · job apps 25 (×2) · study 20 (×3) ·
/// project 35 (×2). Fixed: clean, trash, cat. Everything else is flexible.
struct ScenarioTests {
    private let tz = Fixtures.tokyo

    private final class World {
        let ctx: ModelContext
        var rng = SeededRNG(seed: 7)
        let tz: TimeZone
        init(_ tz: TimeZone) throws {
            ctx = try Fixtures.context()
            self.tz = tz
            try SeedImporter.mergeSeeds(ctx, sideQuestsCSV: Fixtures.csv("side_quests.csv"),
                                        routinesCSV: Fixtures.csv("routine_quests.csv"))
        }

        @discardableResult
        func open(_ day: String, tier: Tier = .normal) throws -> DailyContext {
            try DayService.ensureToday(ctx, now: Fixtures.date(day), in: tz,
                                       inputs: DayInputs(tier: tier), rng: &rng)
        }

        func occurrence(_ prefix: String, due: String) throws -> RoutineOccurrence {
            try #require(try ctx.fetch(FetchDescriptor<RoutineOccurrence>())
                .first { $0.dueDayKey == due && $0.textSnapshot.hasPrefix(prefix) })
        }

        @discardableResult
        func done(_ prefix: String, due: String, on day: String, tier: Tier = .normal) throws -> Int {
            try Completion.completeRoutine(try occurrence(prefix, due: due), on: day, tier: tier,
                                           in: ctx, timeZone: tz)
        }

        @discardableResult
        func ahead(_ prefix: String, on day: String) throws -> Int {
            let r = try #require(try ctx.fetch(FetchDescriptor<RoutineTask>())
                .first { $0.text.hasPrefix(prefix) })
            return try Completion.completeAhead(r, on: day, tier: .normal, in: ctx, timeZone: tz)
        }

        var balance: Int { get throws { try Economy.balance(ctx) } }

        func penalties(on day: String) throws -> [Int] {
            try ctx.fetch(FetchDescriptor<LedgerEntry>())
                .filter { $0.kind == "penalty" && $0.dayKey == day }.map(\.points).sorted()
        }

        var flexibleIDs: Set<UUID> {
            get throws { Set(try ctx.fetch(FetchDescriptor<RoutineTask>()).filter(\.flexibleWithinWeek).map(\.id)) }
        }

        func overdue(on day: String) throws -> [String] {
            Schedule.overdue(try ctx.fetch(FetchDescriptor<RoutineOccurrence>()),
                             flexible: try flexibleIDs, on: day, in: tz).map(\.textSnapshot)
        }

        var backlog: [RoutineOccurrence] {
            get throws { Schedule.backlog(try ctx.fetch(FetchDescriptor<RoutineOccurrence>())) }
        }
    }

    @Test func twoWeeks() throws {
        let w = try World(tz)

        // ── W39 ──────────────────────────────────────────────────────────────────────────────

        // Mon 21: study. Load 1 → 3 slots.
        #expect(try w.open("2026-09-21").randomSlots == 3)
        #expect(try w.done("Study", due: "2026-09-21", on: "2026-09-21") == 20)
        #expect(try w.balance == 20)

        // Tue 22: study, dumbbell. Load 2 → 3 slots. Both done.
        #expect(try w.open("2026-09-22").routineLoad == 2)
        try w.done("Study", due: "2026-09-22", on: "2026-09-22")
        try w.done("Workout: dumbbell", due: "2026-09-22", on: "2026-09-22")
        #expect(try w.balance == 60)

        // Wed 23: trash, dumbbell, study. Load 3 → 2 slots (PLAN §3). Nothing done.
        let wed = try w.open("2026-09-23")
        #expect(wed.routineLoad == 3)
        #expect(wed.randomSlots == 2)

        // Thu 24: Wed is judged — only trash is fixed: day 1, 50% of 5 = 2.5 → −3.
        // Trash made up on day 2 pays half: 2.5 → 3. Wed's study moved to Thu: flexible, full 20.
        try w.open("2026-09-24")
        #expect(try w.penalties(on: "2026-09-23") == [-3])
        #expect(try w.overdue(on: "2026-09-24") == ["Take out the trash"])
        #expect(try w.done("Take out the trash", due: "2026-09-23", on: "2026-09-24") == 3)
        #expect(try w.done("Study", due: "2026-09-23", on: "2026-09-24") == 20)
        #expect(try w.overdue(on: "2026-09-24").isEmpty)
        #expect(try w.balance == 80)                                        // 60 − 3 + 3 + 20

        // Fri 25: Thu is judged — nothing fixed open. Running left undone. Weights done ahead
        // (next due Sat): full 30.
        try w.open("2026-09-25")
        #expect(try w.penalties(on: "2026-09-24").isEmpty)
        #expect(try w.ahead("Workout: weight", on: "2026-09-25") == 30)
        #expect(try w.balance == 110)

        // Sat 26: clean, trash, grocery, bills, project — weights already exists (done ahead),
        // so it isn't due again. Load 5 → 1 slot. Clean and grocery done.
        let sat = try w.open("2026-09-26")
        #expect(sat.routineLoad == 5)
        #expect(sat.randomSlots == 1)
        try w.done("Clean", due: "2026-09-26", on: "2026-09-26")          // 25
        try w.done("Grocery", due: "2026-09-26", on: "2026-09-26")        // 10
        #expect(try w.balance == 145)

        // Sun 27: the app is never opened. No Sunday occurrences exist (cat, weights #2, job #2,
        // project #2), so nothing of Sunday's is charged.

        // ── W40 ──────────────────────────────────────────────────────────────────────────────

        // Mon 28: catch-up judges Sat 26 and Sun 27.
        //   Sat 26: trash day 1 → −3.
        //   Sun 27: trash day 2 → −4 (3.75). Then W39 settles, 50% of base per shortfall:
        //     study    3 due, 3 done (Wed's on Thu)            → 0
        //     dumbbell 2 due, 1 done                           → −10
        //     job apps 1 due (Sun never generated), 0 done     → −13 (12.5)
        //     running  1 due, 0 done                           → −13 (12.5)
        //     weights  1 due (the ahead one), 1 done           → 0
        //     grocery  done                                    → 0
        //     bills    1 due, 0 done                           → −10
        //     project  1 due, 0 done                           → −18 (17.5)
        //   145 − 3 − 4 − 10 − 13 − 13 − 10 − 18 = 74
        #expect(try w.open("2026-09-28").routineLoad == 1)                  // study
        #expect(try w.penalties(on: "2026-09-26") == [-3])
        #expect(try w.penalties(on: "2026-09-27") == [-18, -13, -13, -10, -10, -4])
        #expect(try w.balance == 74)
        #expect(try w.overdue(on: "2026-09-28") == ["Take out the trash"])  // Sat's, day 3
        #expect(try w.backlog.count == 5)            // the five flexible shortfalls, skipped Sunday

        // Tue 29 (tier low): Mon is judged — trash day 3 → −5, then skipped (dated day 4).
        // Mon's study done on Tue: created on a normal day, so it is still the full version —
        // 20 × 1.3 = 26. Tuesday's own two were created on a low day and start out as their
        // downgrade versions, which pay what the lighter thing is worth:
        //   study    → "Just one easy problem"  8 × 1.3 = 10.4 → 10
        //   dumbbell → "Walk, 30 minutes"      10 × 1.3 = 13
        try w.open("2026-09-29", tier: .low)
        #expect(try w.penalties(on: "2026-09-28") == [-5])
        let trash = try w.occurrence("Take out the trash", due: "2026-09-26")
        #expect(trash.skipped)
        #expect(trash.penaltyApplied == 12)                                 // 3 + 4 + 5
        #expect(try w.overdue(on: "2026-09-29").isEmpty)
        #expect(try w.backlog.map(\.textSnapshot).sorted() == [
            "Review bills/statements", "Send job applications", "Take out the trash",
            "Work on project", "Workout: dumbbell training", "Workout: running",
        ])
        #expect(try w.done("Study", due: "2026-09-28", on: "2026-09-29", tier: .low) == 26)
        #expect(try w.occurrence("Study", due: "2026-09-29").displayText == "Just one easy problem")
        #expect(try w.done("Study", due: "2026-09-29", on: "2026-09-29", tier: .low) == 10)
        #expect(try w.occurrence("Workout: dumbbell", due: "2026-09-29").displayText == "Walk, 30 minutes")
        #expect(try w.done("Workout: dumbbell", due: "2026-09-29", on: "2026-09-29", tier: .low) == 13)
        #expect(try w.balance == 74 - 5 + 26 + 10 + 13)                    // 118

        // Wed 30 – Fri Oct 2: never opened, so nothing is generated and nothing charged.

        // Sat Oct 3 — first Saturday: clean, trash, bedsheets, grocery, weights, project.
        // Load 6 → 1 slot. Catch-up judges Tue 29 … Fri 2: nothing fixed was open.
        let sat2 = try w.open("2026-10-03")
        #expect(sat2.routineLoad == 6)
        #expect(sat2.randomSlots == 1)
        #expect(try w.balance == 118)

        // Sun Oct 4: Sat is judged — clean day 1 → −13 (12.5), trash day 1 → −3.
        // Cat done (15); Sat's clean made up late (12.5 → 13); weights Sat (moved) and Sun, 30 each.
        let sun2 = try w.open("2026-10-04")
        #expect(sun2.routineLoad == 4)                                     // cat, weights, job, project
        #expect(try w.penalties(on: "2026-10-03") == [-13, -3])
        try w.done("Cat", due: "2026-10-04", on: "2026-10-04")
        #expect(try w.done("Clean", due: "2026-10-03", on: "2026-10-04") == 13)
        try w.done("Workout: weight", due: "2026-10-03", on: "2026-10-04")
        try w.done("Workout: weight", due: "2026-10-04", on: "2026-10-04")
        #expect(try w.balance == 118 - 16 + 15 + 13 + 60)                  // 190

        // Mon Oct 5: Sun is judged — trash day 2 → −4. W40 settles:
        //   study     2 due (Wed never generated), 2 done     → 0
        //   dumbbell  1 due, 1 done                           → 0
        //   bedsheets 1 due, 0 done                           → −8 (7.5)
        //   grocery   1 due, 0 done                           → −5
        //   weights   2 due, 2 done                           → 0
        //   job apps  1 due, 0 done                           → −13 (12.5)
        //   project   2 due, 0 done                           → −18 × 2
        //   190 − 4 − 8 − 5 − 13 − 36 = 124
        try w.open("2026-10-05")
        #expect(try w.penalties(on: "2026-10-04") == [-18, -18, -13, -8, -5, -4])
        #expect(try w.balance == 124)
        #expect(try w.overdue(on: "2026-10-05") == ["Take out the trash"])  // still on day 3

        // The ledger is the only place the balance lives: re-summing it by kind agrees.
        let ledger = try w.ctx.fetch(FetchDescriptor<LedgerEntry>())
        let earned = ledger.filter { $0.kind == "routine" }.map(\.points).reduce(0, +)
        let charged = ledger.filter { $0.kind == "penalty" }.map(\.points).reduce(0, +)
        #expect(earned == 148 + 137)
        #expect(charged == -(79 + 82))
        #expect(ledger.filter { $0.kind == "skip" }.allSatisfy { $0.points == 0 })
    }

    /// Opening the app twice a day, every day, changes nothing: settlement is idempotent.
    @Test func openingTwiceADayChangesNothing() throws {
        let once = try World(tz), twice = try World(tz)
        for day in DayKey.range(from: "2026-09-21", through: "2026-10-05", in: tz) {
            try once.open(day)
            try twice.open(day)
            try twice.open(day)
        }
        #expect(try once.balance == twice.balance)
        #expect(try twice.ctx.fetch(FetchDescriptor<RoutineOccurrence>()).count
                == once.ctx.fetch(FetchDescriptor<RoutineOccurrence>()).count)
    }

    /// Opened every day, doing nothing at all for W39: what Mon 21 … Sun 27 cost, by hand.
    ///   fixed:    trash Wed 3+4+5 (skipped Sat), trash Sat 3+4 and clean Sat 13+19 (days 1–2
    ///             so far), cat Sun 8 (day 1 so far)
    ///   flexible: study 3×10, dumbbell 2×10, job 2×13, running 13, weights 2×15, grocery 5,
    ///             bills 10, project 2×18
    @Test func aWeekOfDoingNothing() throws {
        let w = try World(tz)
        for day in DayKey.range(from: "2026-09-21", through: "2026-09-28", in: tz) { try w.open(day) }
        // By Mon 28 the days judged are Mon 21 … Sun 27.
        let fixed = (3 + 4 + 5) + (3 + 4) + (13 + 19) + 8
        let flexible = 30 + 20 + 26 + 13 + 30 + 5 + 10 + 36
        #expect(try w.balance == -(fixed + flexible))
    }
}
