import Foundation
import SwiftData

/// What one day shows on the month page (`PLAN.md` §9).
public struct DayMarks: Equatable, Sendable {
    /// Green dots: random quests completed, 0…3. Hidden, epic and ad-hoc-replaced slots don't count;
    /// the T group counts as one.
    public var randomsDone: Int = 0
    /// Blue dot: every clear-gating routine due that day was done on time.
    public var routinesCleared: Bool = false
    /// Star: the hidden quest was completed.
    public var hiddenDone: Bool = false

    public init(randomsDone: Int = 0, routinesCleared: Bool = false, hiddenDone: Bool = false) {
        self.randomsDone = randomsDone
        self.routinesCleared = routinesCleared
        self.hiddenDone = hiddenDone
    }

    public var isEmpty: Bool { randomsDone == 0 && !routinesCleared && !hiddenDone }
}

/// The month page's marks. The rules live only here; the page hands in the rows its `@Query`
/// already holds.
public enum CalendarMarks {
    public static let maxGreenDots = 3

    /// Marks per `dayKey`. Days with nothing to mark are left out.
    public static func marks(quests: [DailyQuest], occurrences: [RoutineOccurrence]) -> [String: DayMarks] {
        var out: [String: DayMarks] = [:]

        for q in quests where q.completedAt != nil && !q.replaced && q.slot != .epic {
            if q.isHiddenSlot {
                out[q.dayKey, default: DayMarks()].hiddenDone = true
            } else {
                var m = out[q.dayKey, default: DayMarks()]
                m.randomsDone = min(maxGreenDots, m.randomsDone + 1)
                out[q.dayKey] = m
            }
        }

        let gating = Dictionary(grouping: occurrences.filter(\.countsForClear), by: \.dueDayKey)
        for (dayKey, due) in gating where due.allSatisfy(doneOnTime) {
            out[dayKey, default: DayMarks()].routinesCleared = true
        }
        return out
    }

    /// Done on its due day, or ahead of it (a flexible routine done earlier in the week). A late
    /// make-up doesn't count — PLAN.md §4: it doesn't count toward that day's full-clear either —
    /// and neither does a skip, so the page tells "did it" apart from "gave up".
    static func doneOnTime(_ o: RoutineOccurrence) -> Bool {
        guard !o.skipped, let done = o.completedDayKey else { return false }
        return done <= o.dueDayKey
    }

    /// Weeks whose epic was completed, by `weekKey` — a week can span two months, so the page
    /// highlights a row by the week it belongs to, never by its position in the grid.
    public static func epicWeeks(_ quests: [DailyQuest]) -> Set<String> {
        Set(quests.filter { $0.slot == .epic && $0.completedAt != nil && !$0.replaced }.map(\.weekKey))
    }
}
