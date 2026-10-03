import Foundation
import Testing
@testable import LifeRPGCore

/// What the Library says about when a routine comes up. The words follow `Schedule` (which days),
/// `Overdue` (what a miss costs) and `Degrade` (lighter versions); the literals here are the
/// contract the page shows.
struct RoutineSchedulePresentationTests {
    private func present(_ kind: RecurrenceKind, _ spec: String, target: Int = 1, flexible: Bool = false,
                         counts: Bool = true, anchor: String? = nil,
                         light: Bool = false) -> RoutineSchedulePresentation {
        RoutineSchedulePresentation(kind: kind, spec: spec, weeklyTarget: target,
                                    flexibleWithinWeek: flexible, countsForClear: counts,
                                    anchorWeekKey: anchor, isLightVersion: light)
    }

    private let fixedMiss = "Left undone, it costs 50% of its points at the end of the day, 75% the next day and 100% the day after, then it is skipped."
    private let flexibleMiss = "No daily charge. On Sunday the week is settled: each session short of the target costs 50% of its points."

    // MARK: set days

    @Test func oneWeekday() {
        let p = present(.weekly, "MON")
        #expect(p.group == .setDays)
        #expect(p.strip == .days)
        #expect(p.weekdays == [true, false, false, false, false, false, false])
        #expect(p.summary == "Mon")
        #expect(p.sentence == "Comes up on Monday.")
        #expect(p.missRule == fixedMiss)
        #expect(p.weeklyTarget == 1)
    }

    @Test func severalWeekdaysAreMondayFirst() {
        let p = present(.weekly, "THU,MON", target: 2)
        #expect(p.weekdays == [true, false, false, true, false, false, false])
        #expect(p.summary == "Mon · Thu")
        #expect(p.sentence == "Comes up on Monday and Thursday.")
        #expect(p.weeklyTarget == 2)
    }

    @Test func sundayIsTheLastCell() {
        let p = present(.weekly, "SAT,SUN", target: 2)
        #expect(p.weekdays == [false, false, false, false, false, true, true])
        #expect(p.summary == "Sat · Sun")
    }

    @Test func threeWeekdaysReadAsAList() {
        let p = present(.weekly, "MON,WED,FRI", target: 3)
        #expect(p.sentence == "Comes up on Monday, Wednesday and Friday.")
    }

    @Test func allSevenDays() {
        let p = present(.weekly, "MON,TUE,WED,THU,FRI,SAT,SUN", target: 7)
        #expect(p.group == .setDays)
        #expect(p.weekdays == Array(repeating: true, count: 7))
        #expect(p.summary == "Every day")
        #expect(p.sentence == "Comes up every day.")
    }

    @Test func everyWeekOnAWeekdayIsASetDay() {
        let p = present(.everyNWeeksOnWeekday, "1:SAT")
        #expect(p.group == .setDays)
        #expect(p.strip == .days)
        #expect(p.weekdays == [false, false, false, false, false, true, false])
        #expect(p.summary == "Sat")
    }

    @Test func notCountingForClearIsNeverCharged() {
        let p = present(.weekly, "MON,THU", counts: false)
        #expect(p.countsForClear == false)
        #expect(p.missRule == "Never charged. It is skipped if it is still open after three days.")
    }

    // MARK: flexible

    @Test func flexibleThreeTimesAWeek() {
        let p = present(.weekly, "MON,TUE,WED", target: 3, flexible: true)
        #expect(p.group == .flexible)
        #expect(p.strip == .anyDay)
        #expect(p.summary == "3× a week · any day")
        #expect(p.sentence == "3 times a week, on any day. It comes due on Monday, Tuesday and Wednesday, and doing it earlier or later that week counts.")
        #expect(p.missRule == flexibleMiss)
        #expect(p.weeklyTarget == 3)
    }

    @Test func flexibleOnceAndTwiceAreSpokenAsWords() {
        #expect(present(.weekly, "FRI", target: 1, flexible: true).sentence
                == "Once a week, on any day. It comes due on Friday, and doing it earlier or later that week counts.")
        #expect(present(.weekly, "TUE,WED", target: 2, flexible: true).sentence
                == "Twice a week, on any day. It comes due on Tuesday and Wednesday, and doing it earlier or later that week counts.")
        #expect(present(.weekly, "FRI", target: 1, flexible: true).summary == "1× a week · any day")
    }

    @Test func flexibleThatIsNotCountedIsOnlySkippedOnSunday() {
        let p = present(.weekly, "FRI", flexible: true, counts: false)
        #expect(p.missRule == "Never charged. Whatever is still open is skipped on Sunday.")
    }

    // MARK: every N days

    @Test func everyThreeDays() {
        let p = present(.everyNDays, "3")
        #expect(p.group == .everyNDays)
        #expect(p.strip == .none)
        #expect(p.weekdays == Array(repeating: false, count: 7))
        #expect(p.summary == "Every 3 days")
        #expect(p.sentence == "Comes up every 3 days, counted from the last time you did it.")
        #expect(p.missRule == fixedMiss)
    }

    @Test func everyDayAsAnInterval() {
        let p = present(.everyNDays, "1")
        #expect(p.summary == "Every day")
        #expect(p.sentence == "Comes up every day, counted from the last time you did it.")
    }

    // MARK: monthly and longer

    @Test func monthlyDay() {
        let p = present(.monthly, "15")
        #expect(p.group == .monthly)
        #expect(p.strip == .none)
        #expect(p.summary == "Day 15")
        #expect(p.sentence == "Comes up on the 15th of each month.")
    }

    @Test func monthlyDayPastTheShortestMonthFallsBack() {
        let p = present(.monthly, "31")
        #expect(p.summary == "Day 31")
        #expect(p.sentence == "Comes up on the 31st of each month, or on the last day of a shorter month.")
        #expect(present(.monthly, "2").sentence == "Comes up on the 2nd of each month.")
        #expect(present(.monthly, "23").sentence == "Comes up on the 23rd of each month.")
        #expect(present(.monthly, "11").sentence == "Comes up on the 11th of each month.")
    }

    @Test func firstAndLastSaturday() {
        let first = present(.nthWeekdayOfMonth, "1:SAT")
        #expect(first.group == .monthly)
        #expect(first.summary == "First Saturday")
        #expect(first.sentence == "Comes up on the first Saturday of each month.")
        let last = present(.nthWeekdayOfMonth, "-1:SAT")
        #expect(last.summary == "Last Saturday")
        #expect(last.sentence == "Comes up on the last Saturday of each month.")
        #expect(present(.nthWeekdayOfMonth, "3:SUN").summary == "Third Sunday")
    }

    @Test func everyTwoWeeksOnSaturday() {
        let p = present(.everyNWeeksOnWeekday, "2:SAT")
        #expect(p.group == .monthly)
        #expect(p.strip == .none)
        #expect(p.summary == "Every 2nd Saturday")
        #expect(p.sentence == "Comes up every 2nd Saturday. Until you first do it, it comes up every week.")
        #expect(p.anchorWeekKey == nil)
        #expect(p.usesAnchorWeek)
    }

    @Test func everyTwoWeeksWithAnAnchorSaysFromWhen() {
        let p = present(.everyNWeeksOnWeekday, "2:SAT", anchor: "2026-W38")
        #expect(p.sentence == "Comes up every 2nd Saturday, counted from the week of 2026-W38.")
        #expect(p.anchorWeekKey == "2026-W38")
        #expect(present(.everyNWeeksOnWeekday, "3:MON").summary == "Every 3rd Monday")
        #expect(present(.everyNWeeksOnWeekday, "4:MON").summary == "Every 4th Monday")
    }

    @Test func anAnchorOnAnyOtherKindIsNotShown() {
        #expect(present(.weekly, "MON", anchor: "2026-W38").anchorWeekKey == nil)
        #expect(present(.weekly, "MON", anchor: "2026-W38").usesAnchorWeek == false)
        #expect(present(.everyNWeeksOnWeekday, "1:SAT", anchor: "2026-W38").usesAnchorWeek == false)
    }

    @Test func flexibleMonthlyStaysMonthlyAndSaysAnyDayThatWeekCounts() {
        let p = present(.nthWeekdayOfMonth, "1:SAT", flexible: true)
        #expect(p.group == .monthly)
        #expect(p.strip == .none)
        #expect(p.summary == "First Saturday")
        #expect(p.sentence == "Comes up on the first Saturday of each month. Doing it any day that week counts.")
        #expect(p.missRule == flexibleMiss)
    }

    // MARK: lighter versions and broken specs

    @Test func aLighterVersionHasNoSchedule() {
        let p = present(.weekly, "", flexible: true, light: true)
        #expect(p.group == .lighterVersion)
        #expect(p.strip == .none)
        #expect(p.summary == "Lighter version")
        #expect(p.sentence == "Offered instead of its original routine on low days. It is never scheduled on its own.")
        #expect(p.missRule == nil)
        #expect(p.weeklyTarget == nil)
    }

    @Test func aSpecThatDoesNotParseIsNotScheduled() {
        let p = present(.weekly, "TUES")
        #expect(p.group == .unscheduled)
        #expect(p.summary == "No schedule")
        #expect(p.sentence == "Its schedule could not be read, so it never comes up.")
        #expect(p.missRule == nil)
    }

    // MARK: grouping and order

    private func routine(_ text: String, _ kind: RecurrenceKind, _ spec: String, target: Int = 1,
                         flexible: Bool = false, active: Bool = true) -> RoutineTask {
        let r = RoutineTask()
        r.text = text; r.kind = kind; r.spec = spec; r.weeklyTarget = target
        r.flexibleWithinWeek = flexible; r.isActive = active
        return r
    }

    private func titles(_ sections: [RoutineSchedulePresentation.Section]) -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: sections.map { ($0.group.rawValue, $0.rows.map(\.routine.text)) })
    }

    @Test func groupsAreInTheStatedOrderAndEmptyOnesAreLeftOut() {
        let rows = [
            routine("monthly", .monthly, "1"),
            routine("every3", .everyNDays, "3"),
            routine("flex", .weekly, "MON", flexible: true),
            routine("set", .weekly, "MON"),
        ]
        let sections = RoutineSchedulePresentation.grouped(rows, lightIDs: [])
        #expect(sections.map(\.group.rawValue) == ["setDays", "flexible", "everyNDays", "monthly"])
        #expect(sections.map(\.group.title) == ["Set days", "Flexible", "Every few days", "Monthly or longer"])
        let none = RoutineSchedulePresentation.grouped([routine("set", .weekly, "MON")], lightIDs: [])
        #expect(none.map(\.group.rawValue) == ["setDays"])
    }

    @Test func setDaysAreOrderedByFirstWeekdayMondayFirstThenText() {
        let rows = [
            routine("Sun only", .weekly, "SUN"),
            routine("B Sat", .weekly, "SAT"),
            routine("A Sat", .weekly, "SAT"),
            routine("Wed and Sat", .weekly, "WED,SAT", target: 2),
            routine("Mon", .weekly, "MON"),
        ]
        let sections = RoutineSchedulePresentation.grouped(rows, lightIDs: [])
        #expect(titles(sections)["setDays"] == ["Mon", "Wed and Sat", "A Sat", "B Sat", "Sun only"])
    }

    @Test func flexibleAreOrderedByTargetDescendingThenText() {
        let rows = [
            routine("Two b", .weekly, "TUE,WED", target: 2, flexible: true),
            routine("Three", .weekly, "MON,TUE,WED", target: 3, flexible: true),
            routine("Two a", .weekly, "SAT,SUN", target: 2, flexible: true),
            routine("One", .weekly, "FRI", target: 1, flexible: true),
        ]
        let sections = RoutineSchedulePresentation.grouped(rows, lightIDs: [])
        #expect(titles(sections)["flexible"] == ["Three", "Two a", "Two b", "One"])
    }

    @Test func everyNDaysAreOrderedByIntervalThenText() {
        let rows = [
            routine("Ten", .everyNDays, "10"),
            routine("Three b", .everyNDays, "3"),
            routine("Three a", .everyNDays, "3"),
        ]
        let sections = RoutineSchedulePresentation.grouped(rows, lightIDs: [])
        #expect(titles(sections)["everyNDays"] == ["Three a", "Three b", "Ten"])
    }

    @Test func monthlyOrdersDaysThenNthWeekdaysThenEveryNWeeks() {
        let rows = [
            routine("every 2nd Sat", .everyNWeeksOnWeekday, "2:SAT"),
            routine("last Sat", .nthWeekdayOfMonth, "-1:SAT"),
            routine("first Sat", .nthWeekdayOfMonth, "1:SAT"),
            routine("day 20", .monthly, "20"),
            routine("day 5", .monthly, "5"),
            routine("every 3rd Mon", .everyNWeeksOnWeekday, "3:MON"),
        ]
        let sections = RoutineSchedulePresentation.grouped(rows, lightIDs: [])
        #expect(titles(sections)["monthly"] == ["day 5", "day 20", "first Sat", "last Sat", "every 2nd Sat", "every 3rd Mon"])
    }

    @Test func inactiveRoutinesStayInTheirGroup() {
        let off = routine("Go to the office", .weekly, "MON,THU", target: 2, active: false)
        let sections = RoutineSchedulePresentation.grouped([off, routine("Run", .weekly, "FRI")], lightIDs: [])
        #expect(sections.count == 1)
        #expect(sections[0].group == .setDays)
        #expect(sections[0].rows.map(\.routine.text) == ["Go to the office", "Run"])
        #expect(sections[0].rows[0].schedule.summary == "Mon · Thu")
    }

    @Test func lighterVersionsAndBrokenOnesCloseTheList() {
        let light = routine("Just the dishes", .weekly, "", flexible: true)
        let broken = routine("Broken", .weekly, "TUES")
        let set = routine("Set", .weekly, "MON")
        let sections = RoutineSchedulePresentation.grouped([light, broken, set], lightIDs: [light.id])
        #expect(sections.map(\.group.rawValue) == ["setDays", "lighterVersion", "unscheduled"])
        #expect(sections.map(\.group.title) == ["Set days", "Lighter versions", "Not scheduled"])
    }

    @Test func aRoutineCarriesItsOwnFields() {
        let r = routine("Swap sheets", .nthWeekdayOfMonth, "1:SAT", flexible: true)
        r.countsForClear = false
        let p = RoutineSchedulePresentation(r, isLightVersion: false)
        #expect(p.group == .monthly)
        #expect(p.countsForClear == false)
        #expect(p.missRule == "Never charged. Whatever is still open is skipped on Sunday.")
    }
}
