import Foundation
import SwiftData

/// An ad-hoc routine replacing a random slot (`PLAN.md` §3).
///
/// The slot is marked `replaced` and no longer counts toward the full-clear or the streak; in its
/// place an occurrence due today is created. The swap itself is free — the cost is that the
/// occurrence now loses points on the fixed ladder if it isn't done. Like completion, it is final.
///
/// The occurrence is **independent of the routine library**: `routineID` stays nil, so it is never
/// flexible, never counts toward a weekly target, never moves `lastCompletedDayKey` and never
/// feeds the next due date. It always gates the clear (`countsForClear = true`), even when picked
/// from a non-scoring routine — otherwise swapping a hard slot for a check-in would be a free pass.
public enum AdHoc {
    public enum Source {
        case routine(RoutineTask)
        case custom(text: String, difficulty: Difficulty)
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        /// Not an open random slot of that day: done, hidden, epic or already replaced.
        case notReplaceable
        case emptyText
        /// Only E / M / H have a range to take a midpoint of.
        case noBasePoints
        /// The routine is already on today's page, scheduled or added.
        case alreadyOnToday

        public var description: String {
            switch self {
            case .notReplaceable: "this slot can't be replaced"
            case .emptyText: "the task needs a description"
            case .noBasePoints: "pick E, M or H"
            case .alreadyOnToday: "that routine is already on today's page"
            }
        }
    }

    /// A custom task's fixed base: the midpoint of its difficulty's random range, rounded — the
    /// same expected value as the slot it would have been drawn into. Nil for T and EPIC.
    public static func basePoints(for difficulty: Difficulty) -> Int? {
        guard [.easy, .medium, .hard].contains(difficulty) else { return nil }
        let r = difficulty.range
        return Scoring.rounded(Double(r.lowerBound + r.upperBound) / 2)
    }

    /// The slots of `dayKey` that can still be replaced: random, not hidden, not epic, not done,
    /// not already replaced. A T group with some items ticked is still open. Easy first, like the
    /// today page.
    public static func replaceableSlots(_ quests: [DailyQuest], on dayKey: String) -> [DailyQuest] {
        quests.filter { isReplaceable($0, on: dayKey) }.sorted { a, b in
            let ra = Difficulty.allCases.firstIndex(of: a.slot) ?? 0
            let rb = Difficulty.allCases.firstIndex(of: b.slot) ?? 0
            return ra == rb ? a.textSnapshot < b.textSnapshot : ra < rb
        }
    }

    /// Active routines not already on `dayKey`'s page: nothing of theirs due that day (scheduled or
    /// added), and nothing from an earlier day still open — an overdue or this-week one is on the
    /// page too, and that is what you'd do instead.
    public static func libraryCandidates(_ routines: [RoutineTask], occurrences: [RoutineOccurrence],
                                         on dayKey: String) -> [RoutineTask] {
        let onPage = onPage(occurrences, on: dayKey)
        return routines.filter { $0.isActive && !onPage.contains($0.id) }.sorted { $0.text < $1.text }
    }

    /// Replaces `quest` with an ad-hoc routine due that day. Returns the new occurrence.
    @discardableResult
    public static func replace(_ quest: DailyQuest,
                               with source: Source,
                               in context: ModelContext,
                               timeZone: TimeZone = .current) throws -> RoutineOccurrence {
        let dayKey = quest.dayKey
        guard isReplaceable(quest, on: dayKey) else { throw Failure.notReplaceable }

        let occurrence = RoutineOccurrence()
        switch source {
        case .routine(let routine):
            let existing = try context.fetch(FetchDescriptor<RoutineOccurrence>())
            guard !onPage(existing, on: dayKey).contains(routine.id) else { throw Failure.alreadyOnToday }
            occurrence.textSnapshot = routine.text
            occurrence.basePoints = routine.basePoints
            occurrence.adHocSourceRoutineID = routine.id
        case .custom(let text, let difficulty):
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw Failure.emptyText }
            guard let base = basePoints(for: difficulty) else { throw Failure.noBasePoints }
            occurrence.textSnapshot = text
            occurrence.basePoints = base
        }
        occurrence.dueDayKey = dayKey
        occurrence.weekKey = DayKey.weekKey(of: dayKey, in: timeZone) ?? quest.weekKey
        occurrence.countsForClear = true
        occurrence.replacesQuestID = quest.id

        context.insert(occurrence)
        quest.replaced = true
        do {
            try context.save()
        } catch {
            quest.replaced = false
            context.delete(occurrence)
            throw error
        }
        return occurrence
    }

    static func isReplaceable(_ quest: DailyQuest, on dayKey: String) -> Bool {
        quest.dayKey == dayKey && !quest.isHiddenSlot && quest.slot != .epic
            && quest.completedAt == nil && !quest.replaced
    }

    private static func onPage(_ occurrences: [RoutineOccurrence], on dayKey: String) -> Set<UUID> {
        Set(occurrences.filter { o in
            o.dueDayKey == dayKey || (o.dueDayKey < dayKey && Schedule.isOpen(o))
        }.flatMap { [$0.routineID, $0.adHocSourceRoutineID] }
            .compactMap { $0 })
    }
}
