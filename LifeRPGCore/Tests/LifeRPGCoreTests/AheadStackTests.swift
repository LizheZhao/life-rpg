import Foundation
import Testing
@testable import LifeRPGCore

/// The Ahead section's rows and header numbers. Which routines are ahead is `Schedule`'s rule
/// (`ScheduleTests`, `FlexibleAheadTests`); these assert what the section says about them.
/// 2026-10-02 is a Friday; W40 runs Mon 2026-09-28 to Sun 2026-10-04.
struct AheadStackTests {
    private let tz = Fixtures.tokyo
    private let friday = "2026-10-02"
    private let week = "2026-W40"

    private func routine(_ text: String, base: Int = 30, spec: String = "SAT", target: Int = 1,
                         flexible: Bool = true) -> RoutineTask {
        let r = RoutineTask()
        r.text = text
        r.spec = spec
        r.basePoints = base
        r.weeklyTarget = target
        r.flexibleWithinWeek = flexible
        return r
    }

    private func occurrence(_ r: RoutineTask, due: String, base: Int? = nil, doneOn: String? = nil,
                            paid: Int? = nil) -> RoutineOccurrence {
        let o = RoutineOccurrence()
        o.textSnapshot = r.text
        o.basePoints = base ?? r.basePoints
        o.dueDayKey = due
        o.weekKey = week
        o.routineID = r.id
        o.completedDayKey = doneOn
        o.awardedPoints = paid
        return o
    }

    private func state(_ routines: [RoutineTask], _ occurrences: [RoutineOccurrence] = [],
                       today: String? = nil, tier: Tier = .normal) -> AheadState {
        let flexible = Set(routines.filter(\.flexibleWithinWeek).map(\.id))
        let day = today ?? friday
        return AheadState(routines: routines, occurrences: occurrences, flexible: flexible,
                          today: day, tier: tier, in: tz) { o, placement in
            RoutineRowState(o, placement: placement, routine: routines.first { $0.id == o.routineID },
                            flexible: true, today: day, tier: tier, level: 1,
                            quests: [], occurrences: occurrences)
        }
    }

    private func candidate(_ s: AheadState, _ index: Int = 0) -> AheadCandidateState? {
        guard s.items.indices.contains(index), case .candidate(let c) = s.items[index] else { return nil }
        return c
    }

    @Test func nothingAheadMeansNoSection() {
        let s = state([routine("Strength", flexible: false)])
        #expect(s.isEmpty)
        #expect(s.summary == "0 open")
        #expect(s.billText == nil)
    }

    @Test func aCandidateReadsLikeARoutineRow() throws {
        let r = routine("Workout: weight training", base: 30)
        let s = state([r])
        let c = try #require(candidate(s))
        #expect(c.id == r.id)
        #expect(c.title == "Workout: weight training")
        #expect(c.doodle == DoodleKey.forText("Workout: weight training"))
        #expect(c.pills == [.init("+30", .payout), .init("due tomorrow", .plain)])
        #expect(c.accessibilityLabel == "Workout: weight training, pays 30 coins, due tomorrow")
        #expect(c.accessibilityValue == "not done")
        #expect(s.summary == "1 open")
    }

    @Test func dueDayIsCountedFromToday() throws {
        let r = routine("Strength", spec: "SAT")
        #expect(try #require(candidate(state([r], today: "2026-09-30"))).pills.last
                == .init("due in 3 days", .plain))
        #expect(try #require(candidate(state([r], today: "2026-10-01"))).pills.last
                == .init("due in 2 days", .plain))
    }

    @Test func strikesAreThisWeeksCompletions() throws {
        let r = routine("Strength", spec: "THU,SAT", target: 2)
        let thursday = occurrence(r, due: "2026-10-01", doneOn: "2026-10-01", paid: 30)
        let c = try #require(candidate(state([r], [thursday])))
        #expect(c.pills[1] == .init("1 strike this week", .plain))
    }

    @Test func aLowDayPaysOnlyTheLightVersionsOnOffer() throws {
        let light = routine("Stretch 15 min", base: 20, spec: "SAT", flexible: false)
        let lighter = routine("Stretch 5 min", base: 10, spec: "SAT", flexible: false)
        let original = routine("Strength session", base: 40)
        original.downgradeIDs = [light.id, lighter.id]
        let all = [original, light, lighter]
        #expect(try #require(candidate(state(all, tier: .normal))).pills[0] == .init("+40", .payout))
        // 1.3 on a low day; the original is not what a lighter-version day pays.
        #expect(try #require(candidate(state(all, tier: .low))).pills[0] == .init("+13–26", .payout))
        #expect(state(all, tier: .low).items.count == 1)
    }

    @Test func openDoneAndCandidateRowsKeepTheirOrderAndThePlacementIsThisWeek() throws {
        let open = routine("Strength session", base: 20)
        let aheadDone = routine("Run", base: 25)
        let next = routine("Yoga", base: 10, spec: "SUN")
        let openOccurrence = occurrence(open, due: "2026-09-30")
        let doneOccurrence = occurrence(aheadDone, due: "2026-10-03", doneOn: friday, paid: 25)
        let s = state([open, aheadDone, next], [openOccurrence, doneOccurrence])

        #expect(s.items.count == 3)
        guard case .routine(let first) = s.items[0], case .routine(let second) = s.items[1] else {
            Issue.record("expected two routine rows first")
            return
        }
        #expect(first.id == openOccurrence.id)
        #expect(!first.isDone)
        #expect(first.notes == ["Not done · due Wed Sep 30"])
        #expect(second.id == doneOccurrence.id)
        #expect(second.isDone)
        #expect(second.notes == ["Done ahead · counts for Sat Oct 3"])
        let c = try #require(candidate(s, 2))
        #expect(c.title == "Yoga")
        #expect(c.pills.last == .init("due in 2 days", .plain))
    }

    /// What is due today sits under Routines and carries its own bill; the Ahead header adds up
    /// only the rows inside that section, so the number beside "Ahead this week" never includes
    /// a routine the reader cannot see there.
    @Test func headerBillCountsOnlyTheRowsInTheSection() {
        let earlier = routine("Strength session", base: 20)
        let dueToday = routine("Grocery shopping", base: 10)
        let s = state([earlier, dueToday],
                      [occurrence(earlier, due: "2026-09-30"), occurrence(dueToday, due: friday)])
        #expect(s.billText == "−10 Sun night")          // Strength's 50% of 20, not Grocery's 5 on top
        #expect(s.accessibilityLabel == "Ahead this week, 1 open, minus 10 coins Sunday night")
    }

    @Test func noBillInTheSectionWhenOnlyTodaysRoutineOwes() {
        let dueToday = routine("Grocery shopping", base: 10)
        let s = state([dueToday], [occurrence(dueToday, due: friday)])
        #expect(s.billText == nil)
    }

    @Test func headerCountsOpenAndDoneAndNamesSundaysBill() {
        let open = routine("Strength session", base: 20)
        let aheadDone = routine("Run", base: 25)
        let next = routine("Yoga", base: 10, spec: "SUN")
        let s = state([open, aheadDone, next],
                      [occurrence(open, due: "2026-09-30"),
                       occurrence(aheadDone, due: "2026-10-03", doneOn: friday, paid: 25)])
        #expect(s.openCount == 2)
        #expect(s.doneCount == 1)
        #expect(s.summary == "2 open")
        // Half of the open session's 20 base points: what `Overdue.weekly` will charge on Sunday.
        #expect(s.billText == "−10 Sun night")
        #expect(s.accessibilityLabel == "Ahead this week, 2 open, 1 done, minus 10 coins Sunday night")
    }
}
