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
    /// The journal mark under the day: 1 to 3, darker for a longer entry (`JournalMarks.levels`),
    /// 0 when nothing was written.
    public var journalLevel: Int = 0

    public init(randomTiers: [Difficulty] = [], routinesCleared: Bool = false, hiddenDone: Bool = false,
                journalLevel: Int = 0) {
        self.randomTiers = randomTiers
        self.routinesCleared = routinesCleared
        self.hiddenDone = hiddenDone
        self.journalLevel = journalLevel
    }

    /// Random quests shown as dots, 0…`CalendarMarks.maxRandomDots`.
    public var randomsDone: Int { randomTiers.count }
}

/// The month page's marks. The rules live only here; the page hands in the rows its `@Query`
/// already holds.
public enum CalendarMarks {
    public static let maxRandomDots = 3

    /// Marks per `dayKey`. Days with nothing to mark are left out. `journalLevels` is
    /// `JournalMarks.levels`, passed in because the journal is its own table: a day with only a
    /// journal mark still gets an entry.
    public static func marks(quests: [DailyQuest], occurrences: [RoutineOccurrence],
                             journalLevels: [String: Int] = [:]) -> [String: DayMarks] {
        var out: [String: DayMarks] = [:]
        for (dayKey, level) in journalLevels where level > 0 {
            out[dayKey, default: DayMarks()].journalLevel = level
        }
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

    /// How much of each day's asked work was done: the ring around the day number. Counted are the
    /// day's random quests (the T group as one; hidden, epic and anything swapped or cancelled
    /// away left out) and its clear-gating routines (`doneOnTime`, so a late make-up does not close
    /// the ring). Days with nothing asked are left out.
    public static func progress(quests: [DailyQuest], occurrences: [RoutineOccurrence]) -> [String: DayProgress] {
        var out: [String: DayProgress] = [:]
        for q in quests where !q.replaced && q.slot != .epic && !q.isHiddenSlot {
            out[q.dayKey, default: DayProgress()].asked += 1
            if q.completedAt != nil { out[q.dayKey, default: DayProgress()].done += 1 }
        }
        for o in occurrences where o.countsForClear && !o.isReplaced {
            out[o.dueDayKey, default: DayProgress()].asked += 1
            if doneOnTime(o) { out[o.dueDayKey, default: DayProgress()].done += 1 }
        }
        return out
    }

    /// Every epic as a highlighter stroke under the dates, oldest first: from the day it was drawn
    /// to the day it was finished, or, unfinished, to its last day (`Epic.lastDayKey`, extensions
    /// included). Swapped-away rows are left out. Finished strokes carry their place among the
    /// finished ones (`doneIndex`), so the page can give each one a different colour from the one
    /// before; an unfinished stroke has none and is grey.
    public static func epicSpans(_ quests: [DailyQuest], in timeZone: TimeZone = .current) -> [EpicSpan] {
        var spans: [EpicSpan] = []
        var doneCount = 0
        for q in quests.filter({ $0.slot == .epic && !$0.replaced }).sorted(by: { $0.dayKey < $1.dayKey }) {
            if let done = q.completedAt {
                spans.append(EpicSpan(start: q.dayKey, end: max(q.dayKey, done.dayKey(in: timeZone)), doneIndex: doneCount))
                doneCount += 1
            } else if let last = Epic.lastDayKey(of: q, in: timeZone) {
                spans.append(EpicSpan(start: q.dayKey, end: last, doneIndex: nil))
            }
        }
        return spans
    }
}

/// The ring around a day number: `done` of `asked`.
public struct DayProgress: Equatable, Sendable {
    public var asked: Int = 0
    public var done: Int = 0

    public init(asked: Int = 0, done: Int = 0) {
        self.asked = asked
        self.done = done
    }

    /// 0…1; 0 when nothing was asked.
    public var fraction: Double { asked == 0 ? 0 : min(Double(done) / Double(asked), 1) }
}

/// One epic on the month page, from `start` to `end` inclusive.
public struct EpicSpan: Equatable, Sendable {
    public let start: String
    public let end: String
    /// Nil while unfinished; otherwise 0 for the first epic ever finished, 1 for the next, and so on.
    public let doneIndex: Int?

    public init(start: String, end: String, doneIndex: Int?) {
        self.start = start
        self.end = end
        self.doneIndex = doneIndex
    }

    public func covers(_ dayKey: String) -> Bool { start <= dayKey && dayKey <= end }
}
