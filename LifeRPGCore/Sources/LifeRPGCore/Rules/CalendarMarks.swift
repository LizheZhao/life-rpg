import Foundation
import SwiftData

/// What one day shows on the month page (`PLAN.md` §9).
public struct DayMarks: Equatable, Sendable {
    /// One dot per completed random quest, coloured by its tier: easiest first, at most
    /// `CalendarMarks.maxRandomDots`. Hidden, epic and ad-hoc-replaced slots don't count; the T
    /// group counts as one and is tier `trivial`. When more are done than fit, the **easiest**
    /// ones are kept (the list is sorted, then cut), so a harder fourth completion never changes
    /// the dots already shown.
    public var randomTiers: [Difficulty] = []
    /// Marker: every clear-gating routine due that day was done on time.
    public var routinesCleared: Bool = false
    /// Star: the hidden quest was completed.
    public var hiddenDone: Bool = false

    public init(randomTiers: [Difficulty] = [], routinesCleared: Bool = false, hiddenDone: Bool = false) {
        self.randomTiers = randomTiers
        self.routinesCleared = routinesCleared
        self.hiddenDone = hiddenDone
    }

    /// Random quests shown as dots, 0…`CalendarMarks.maxRandomDots`.
    public var randomsDone: Int { randomTiers.count }

    public var isEmpty: Bool { randomTiers.isEmpty && !routinesCleared && !hiddenDone }
}

/// The month page's marks. The rules live only here; the page hands in the rows its `@Query`
/// already holds.
public enum CalendarMarks {
    public static let maxRandomDots = 3

    /// Marks per `dayKey`. Days with nothing to mark are left out.
    public static func marks(quests: [DailyQuest], occurrences: [RoutineOccurrence]) -> [String: DayMarks] {
        var out: [String: DayMarks] = [:]
        var tiers: [String: [Difficulty]] = [:]

        for q in quests where q.completedAt != nil && !q.replaced && q.slot != .epic {
            if q.isHiddenSlot {
                out[q.dayKey, default: DayMarks()].hiddenDone = true
            } else {
                // The group sits on the trivial slot, so `q.slot` already says `trivial` for it.
                tiers[q.dayKey, default: []].append(q.slot)
            }
        }
        let order = Difficulty.allCases
        for (dayKey, list) in tiers {
            out[dayKey, default: DayMarks()].randomTiers = Array(
                list.sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }.prefix(maxRandomDots))
        }

        let gating = Dictionary(grouping: occurrences.filter { $0.countsForClear && !$0.isReplaced }, by: \.dueDayKey)
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

    /// Weeks in which an epic was completed, as `weekKey`s — a week can span two months, so the
    /// page highlights a row by the week it belongs to, never by its position in the grid.
    ///
    /// **The week it was completed in, not the row's `weekKey`** (decided with the user). An
    /// extended epic drawn in W38 and finished in W39 lights up W39, and W38 stays plain.
    public static func epicWeeks(_ quests: [DailyQuest], in timeZone: TimeZone = .current) -> Set<String> {
        Set(quests.compactMap { q in
            guard q.slot == .epic, !q.replaced, let done = q.completedAt else { return nil }
            return done.weekKey(in: timeZone)
        })
    }
}
