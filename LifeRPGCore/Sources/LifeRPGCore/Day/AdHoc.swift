import Foundation
import SwiftData

/// An ad-hoc routine: replacing a random slot (`replace`), or added on top of the day (`add`)
/// (`PLAN.md` §3).
///
/// The slot is marked `replaced` and no longer counts toward the full-clear or the streak; in its
/// place an occurrence due today is created. The swap itself is free — the cost is that the
/// occurrence now loses points on the fixed ladder if it isn't done. Like completion, it is final.
///
/// The occurrence is **independent of the routine library**: `routineID` stays nil, so it is never
/// flexible, never moves `lastCompletedDayKey` and never feeds the next due date. Done, one picked
/// from the library does count toward that routine's weekly target (`Schedule.doneThisWeek`). It always gates the clear (`countsForClear = true`), even when picked
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
        /// Replacing a routine: done, skipped, already replaced, or outside its round / week.
        case routineNotReplaceable
        /// Replacing a routine with something lighter would be a free cancel (a cancel costs 200).
        case tooLight(minimum: Int)

        public var description: String {
            switch self {
            case .notReplaceable: "this slot can't be replaced"
            case .emptyText: "the task needs a description"
            case .noBasePoints: "pick E, M or H"
            case .alreadyOnToday: "that routine is already on today's page"
            case .routineNotReplaceable: "this routine can't be replaced"
            case .tooLight(let minimum): "pick something worth at least \(minimum) points"
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

    /// The occurrence that puts `routine` on `dayKey`'s page — what `libraryCandidates` leaves
    /// out, so the sheet can list it separately instead of hiding it (a Saturday session still open
    /// on Sunday used to look like it wasn't in the library at all). An open one first, oldest
    /// first — that is the one to mark done — else the one done today. Nil = not on the page.
    public static func onPageOccurrence(for routine: RoutineTask, occurrences: [RoutineOccurrence],
                                        on dayKey: String) -> RoutineOccurrence? {
        let mine = occurrences.filter { o in
            (o.routineID == routine.id || o.adHocSourceRoutineID == routine.id) && !o.isReplaced
                && (o.dueDayKey == dayKey || (o.dueDayKey < dayKey && Schedule.isOpen(o)))
        }.sorted { $0.dueDayKey < $1.dueDayKey }
        return mine.first(where: Schedule.isOpen) ?? mine.first
    }

    /// Library routines whose wording is close to `text` — shown under a custom task as it is typed,
    /// so a routine that already exists is used instead of retyped (a custom task counts toward no
    /// weekly target). Best match first, at most `limit`.
    ///
    /// Words are compared case-insensitively with filler words dropped, a shorter word matching the
    /// start of a longer one ("shop" / "shopping"); CJK text is compared character by character.
    /// A routine matches when it covers at least half of what was typed. Downgrade versions are left
    /// out: they are only ever reached through their routine.
    public static func similarRoutines(to text: String, in routines: [RoutineTask],
                                       limit: Int = 3) -> [RoutineTask] {
        let typed = tokens(text)
        guard !typed.isEmpty else { return [] }
        let downgrades = Degrade.versionIDs(in: routines)
        let scored: [(RoutineTask, Double)] = routines.compactMap { r in
            guard r.isActive, !downgrades.contains(r.id) else { return nil }
            let theirs = tokens(r.text)
            let hits = typed.filter { t in theirs.contains { sameWord(t, $0) } }.count
            let score = Double(hits) / Double(typed.count)
            return hits > 0 && score >= 0.5 ? (r, score) : nil
        }
        return scored.sorted { $0.1 == $1.1 ? $0.0.text < $1.0.text : $0.1 > $1.1 }
            .prefix(limit).map(\.0)
    }

    private static let fillerWords: Set<String> = [
        "a", "an", "and", "the", "of", "to", "for", "in", "on", "out", "with", "my", "some", "just",
    ]

    static func tokens(_ text: String) -> Set<String> {
        var out: Set<String> = []
        var word = ""
        func flush() {
            if !word.isEmpty, !fillerWords.contains(word) { out.insert(word) }
            word = ""
        }
        for ch in text.lowercased() {
            if ch.unicodeScalars.contains(where: isCJK) {
                flush()
                out.insert(String(ch))
            } else if ch.isLetter || ch.isNumber {
                word.append(ch)
            } else {
                flush()
            }
        }
        flush()
        return out
    }

    private static func isCJK(_ s: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(s.value) || (0x3400...0x4DBF).contains(s.value)
    }

    private static func sameWord(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let (short, long) = a.count <= b.count ? (a, b) : (b, a)
        return short.count >= 4 && long.hasPrefix(short)
    }

    /// Replaces `quest` with an ad-hoc routine due that day. Returns the new occurrence.
    @discardableResult
    public static func replace(_ quest: DailyQuest,
                               with source: Source,
                               in context: ModelContext,
                               timeZone: TimeZone = .current) throws -> RoutineOccurrence {
        let dayKey = quest.dayKey
        guard isReplaceable(quest, on: dayKey) else { throw Failure.notReplaceable }

        let occurrence = try makeOccurrence(source, on: dayKey, in: context, timeZone: timeZone)
        occurrence.countsForClear = true
        occurrence.replacesQuestID = quest.id

        context.insert(occurrence)
        quest.replaced = true
        quest.replacedReason = .adHoc
        do {
            try context.save()
        } catch {
            quest.replaced = false
            quest.replacedReasonRaw = nil
            context.delete(occurrence)
            throw error
        }
        return occurrence
    }

    /// Adds a routine for `dayKey` **on top of** the day, replacing nothing (decided with the
    /// user; replacing a slot is `replace`, from that slot's swipe action).
    ///
    /// Extra work, so it is never a liability: `countsForClear = false`, which means it doesn't
    /// gate the hidden quest and is never charged when left undone — its round still ends and it is
    /// skipped on day 4. Done, it pays like any routine. Same independence from the library as a
    /// replacement: `routineID` stays nil.
    @discardableResult
    public static func add(_ source: Source, on dayKey: String, in context: ModelContext,
                           timeZone: TimeZone = .current) throws -> RoutineOccurrence {
        let occurrence = try makeOccurrence(source, on: dayKey, in: context, timeZone: timeZone)
        occurrence.countsForClear = false
        context.insert(occurrence)
        do {
            try context.save()
        } catch {
            context.delete(occurrence)
            throw error
        }
        return occurrence
    }

    // MARK: replacing a routine

    /// Whether `o` can be swapped on `dayKey`: still open and still completable that day (its due
    /// day or overdue day 2–3 for a fixed one, any later day of its week for a flexible one).
    public static func isReplaceable(_ o: RoutineOccurrence, flexible: Bool, on dayKey: String,
                                     in timeZone: TimeZone = .current) -> Bool {
        Schedule.isOpen(o) && !o.isReplaced
            && Completion.routinePayout(o, flexible: flexible, on: dayKey, tier: .normal, in: timeZone) != nil
    }

    /// The least a replacement may be worth: what the version currently asked for is worth.
    public static func minimumBase(replacing o: RoutineOccurrence) -> Int { o.effectiveBasePoints }

    /// The custom difficulties heavy enough to replace `o` (their midpoint is at least its base).
    public static func customDifficulties(replacing o: RoutineOccurrence) -> [Difficulty] {
        [.easy, .medium, .hard].filter { (basePoints(for: $0) ?? 0) >= minimumBase(replacing: o) }
    }

    /// Swaps an open routine for an ad-hoc one, free, as long as the new one is worth **at least as
    /// much** (decided with the user) — otherwise it would be a free cancel.
    ///
    /// The old occurrence is closed (`skipped`, with `replacedByID`), so it is never charged again
    /// and no longer gates the clear; deductions already charged stay. The new one gates exactly
    /// when the old one did. For a fixed routine it keeps the old due day, so the overdue ladder
    /// carries on where it was — swapping doesn't buy a fresh round. A flexible session had no
    /// ladder to carry: the new one is due on `dayKey`, and the swapped session drops out of that
    /// week's target (`Overdue.weekly`).
    @discardableResult
    public static func replaceRoutine(_ o: RoutineOccurrence, flexible: Bool, with source: Source,
                                      on dayKey: String, in context: ModelContext,
                                      timeZone: TimeZone = .current) throws -> RoutineOccurrence {
        guard isReplaceable(o, flexible: flexible, on: dayKey, in: timeZone) else {
            throw Failure.routineNotReplaceable
        }
        let fresh = try makeOccurrence(source, on: dayKey, in: context, timeZone: timeZone)
        let minimum = minimumBase(replacing: o)
        guard fresh.basePoints >= minimum else { throw Failure.tooLight(minimum: minimum) }
        if !flexible {
            fresh.dueDayKey = o.dueDayKey
            fresh.weekKey = o.weekKey
        }
        fresh.countsForClear = o.countsForClear

        context.insert(fresh)
        o.skipped = true
        o.replacedByID = fresh.id
        do {
            try context.save()
        } catch {
            o.skipped = false
            o.replacedByID = nil
            context.delete(fresh)
            throw error
        }
        return fresh
    }

    /// The occurrence both `replace` and `add` create, before either says whether it gates.
    private static func makeOccurrence(_ source: Source, on dayKey: String, in context: ModelContext,
                                       timeZone: TimeZone) throws -> RoutineOccurrence {
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
        occurrence.weekKey = DayKey.weekKey(of: dayKey, in: timeZone) ?? ""
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
