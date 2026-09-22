import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// The month page's dots, star and epic-week highlight (PLAN §9).
struct CalendarMarksTests {
    private let day = "2026-09-17"

    private func quest(_ dayKey: String, _ slot: Difficulty = .easy, done: Bool = true,
                       hidden: Bool = false, replaced: Bool = false, week: String = "2026-W38") -> DailyQuest {
        let q = DailyQuest()
        q.dayKey = dayKey
        q.weekKey = week
        q.slot = slot
        q.isHiddenSlot = hidden
        q.replaced = replaced
        q.completedAt = done ? Fixtures.date(dayKey) : nil
        return q
    }

    private func occurrence(due: String, completed: String? = nil, skipped: Bool = false,
                            countsForClear: Bool = true) -> RoutineOccurrence {
        let o = RoutineOccurrence()
        o.dueDayKey = due
        o.completedDayKey = completed
        o.skipped = skipped
        o.countsForClear = countsForClear
        return o
    }

    @Test func greenDotsCountCompletedRandomQuests() {
        let marks = CalendarMarks.marks(quests: [
            quest(day, .easy), quest(day, .medium), quest(day, .hard, done: false),
        ], occurrences: [])
        #expect(marks[day] == DayMarks(randomsDone: 2))
    }

    /// Hidden is the star, not a green dot; epic and ad-hoc-replaced slots are neither.
    @Test func hiddenEpicAndReplacedAreNotGreenDots() {
        let marks = CalendarMarks.marks(quests: [
            quest(day, .easy, hidden: true),
            quest(day, .epic),
            quest(day, .medium, replaced: true),
        ], occurrences: [])
        #expect(marks[day] == DayMarks(randomsDone: 0, hiddenDone: true))
    }

    @Test func greenDotsCapAtThree() {
        let marks = CalendarMarks.marks(quests: (0..<4).map { _ in quest(day) }, occurrences: [])
        #expect(marks[day]?.randomsDone == 3)
    }

    @Test func blueDotNeedsEveryGatingRoutineDoneOnTheDay() {
        let marks = CalendarMarks.marks(quests: [], occurrences: [
            occurrence(due: day, completed: day),
            occurrence(due: day, completed: day),
        ])
        #expect(marks[day] == DayMarks(routinesCleared: true))
    }

    /// Decided with the user: a late make-up and a skip both withhold the blue dot — the page tells
    /// "did it" apart from "made it up later" and "gave up".
    @Test func lateOrSkippedWithholdsTheBlueDot() {
        let late = CalendarMarks.marks(quests: [], occurrences: [
            occurrence(due: day, completed: day),
            occurrence(due: day, completed: "2026-09-18"),
        ])
        #expect(late[day] == nil)
        let skipped = CalendarMarks.marks(quests: [], occurrences: [
            occurrence(due: day, completed: day),
            occurrence(due: day, skipped: true),
        ])
        #expect(skipped[day] == nil)
        let open = CalendarMarks.marks(quests: [], occurrences: [occurrence(due: day)])
        #expect(open[day] == nil)
    }

    /// A flexible routine done ahead earlier in the week was done, not given up on.
    @Test func doneAheadCountsForItsDueDay() {
        let marks = CalendarMarks.marks(quests: [], occurrences: [
            occurrence(due: day, completed: "2026-09-15"),
        ])
        #expect(marks[day]?.routinesCleared == true)
    }

    /// Check-in routines don't gate the day, so they neither give nor withhold the dot.
    @Test func nonGatingRoutinesAreIgnored() {
        let onlyCheckIn = CalendarMarks.marks(quests: [], occurrences: [
            occurrence(due: day, completed: day, countsForClear: false),
        ])
        #expect(onlyCheckIn[day] == nil)
        let missedCheckIn = CalendarMarks.marks(quests: [], occurrences: [
            occurrence(due: day, completed: day),
            occurrence(due: day, countsForClear: false),
        ])
        #expect(missedCheckIn[day]?.routinesCleared == true)
    }

    @Test func emptyDaysAreLeftOut() {
        #expect(CalendarMarks.marks(quests: [quest(day, done: false)], occurrences: []).isEmpty)
    }

    @Test func epicWeeksAreJudgedByWeekKey() {
        let weeks = CalendarMarks.epicWeeks([
            quest("2026-09-28", .epic, week: "2026-W40"),                 // Monday of W40, done
            quest("2026-09-21", .epic, done: false, week: "2026-W39"),    // open: not highlighted
            quest("2026-09-17", .hard, week: "2026-W38"),                 // not an epic
        ])
        #expect(weeks == ["2026-W40"])
    }

    /// The page passes its `@Query` arrays; the store gives the same answer from the same rows.
    @Test func readsStoredRows() throws {
        let ctx = try Fixtures.context()
        ctx.insert(quest(day, .medium))
        Fixtures.occurrence(ctx, "Run", due: day, completed: day)
        try ctx.save()
        let marks = CalendarMarks.marks(quests: try ctx.fetch(FetchDescriptor<DailyQuest>()),
                                        occurrences: try ctx.fetch(FetchDescriptor<RoutineOccurrence>()))
        #expect(marks[day] == DayMarks(randomsDone: 1, routinesCleared: true))
    }
}
