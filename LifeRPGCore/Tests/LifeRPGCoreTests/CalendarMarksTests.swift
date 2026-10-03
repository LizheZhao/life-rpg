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

    @Test func randomDotsAreTheTiersOfCompletedRandomQuests() {
        let marks = CalendarMarks.marks(quests: [
            quest(day, .hard), quest(day, .easy), quest(day, .medium, done: false),
        ], occurrences: [])
        // Easiest first, whatever order the rows arrive in; the open medium is not a dot.
        #expect(marks[day] == DayMarks(randomTiers: [.easy, .hard]))
        #expect(marks[day]?.randomsDone == 2)
    }

    /// Hidden is the star, not a green dot; epic and ad-hoc-replaced slots are neither.
    @Test func hiddenEpicAndReplacedAreNotGreenDots() {
        let marks = CalendarMarks.marks(quests: [
            quest(day, .easy, hidden: true),
            quest(day, .epic),
            quest(day, .medium, replaced: true),
        ], occurrences: [])
        #expect(marks[day] == DayMarks(hiddenDone: true))
    }

    /// The cap keeps the three **easiest** (the rule is "sorted easiest first, then the first
    /// three"), so a fourth, harder completion never pushes a lower tier's dot off the day.
    @Test func randomDotsKeepTheThreeEasiest() {
        let four = CalendarMarks.marks(quests: [.hard, .trivial, .medium, .easy].map { quest(day, $0) },
                                       occurrences: [])
        #expect(four[day]?.randomTiers == [.trivial, .easy, .medium])
        let same = CalendarMarks.marks(quests: (0..<4).map { _ in quest(day) }, occurrences: [])
        #expect(same[day]?.randomTiers == [.easy, .easy, .easy])
        #expect(same[day]?.randomsDone == 3)
    }

    /// The micro-action group is one quest on the trivial slot: one trivial dot.
    @Test func microActionGroupIsOneTrivialDot() {
        let group = quest(day, .trivial)
        group.trivialGroup = ["Stretch", "Water", "Tidy"]
        group.trivialDone = [true, true, true]
        let marks = CalendarMarks.marks(quests: [group, quest(day, .medium)], occurrences: [])
        #expect(marks[day]?.randomTiers == [.trivial, .medium])
    }

    /// The app colours a dot with `QuestTint(difficulty)`; the mapping is Core's.
    @Test func tierToTintMapping() {
        #expect(Difficulty.allCases.map { QuestTint($0) } == [.trivial, .easy, .medium, .hard, .epic])
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
        ], in: Fixtures.tokyo)
        #expect(weeks == ["2026-W40"])
    }

    /// Decided with the user: an extended epic lights up the week it was **completed** in.
    /// Drawn Monday of W38, extended, finished Wednesday of W39 → W39, and W38 stays plain.
    @Test func extendedEpicHighlightsTheWeekItWasCompleted() {
        let epic = quest("2026-09-14", .epic, done: false, week: "2026-W38")
        epic.extensionCount = 1
        epic.completedAt = Fixtures.date("2026-09-23")
        #expect(CalendarMarks.epicWeeks([epic], in: Fixtures.tokyo) == ["2026-W39"])
    }

    /// The page passes its `@Query` arrays; the store gives the same answer from the same rows.
    @Test func readsStoredRows() throws {
        let ctx = try Fixtures.context()
        ctx.insert(quest(day, .medium))
        Fixtures.occurrence(ctx, "Run", due: day, completed: day)
        try ctx.save()
        let marks = CalendarMarks.marks(quests: try ctx.fetch(FetchDescriptor<DailyQuest>()),
                                        occurrences: try ctx.fetch(FetchDescriptor<RoutineOccurrence>()))
        #expect(marks[day] == DayMarks(randomTiers: [.medium], routinesCleared: true))
    }
}
