import Foundation

/// How far a Today section has got. The hand label beside its header: `1 / 3 done`, and `cleared`
/// once nothing is left, which is what stays when every card has moved into the Completed stack.
public struct SectionProgress: Equatable, Sendable {
    public static let clearedLabel = "cleared"

    public let done: Int
    public let total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }

    /// Nil for an empty section: there is nothing to report progress on.
    public var handLabel: String? {
        guard total > 0 else { return nil }
        return done == total ? Self.clearedLabel : "\(done) / \(total) done"
    }
}

extension EpicCardState {
    /// The hand label of the epic's section header.
    public var sectionLabel: String { isDone ? SectionProgress.clearedLabel : "this week" }
}

/// One finished thing, as the state Core already builds for its open card.
public enum CompletedItem: Equatable, Identifiable, Sendable {
    case quest(QuestCardState)
    case routine(RoutineRowState)
    case epic(EpicCardState)

    public var id: UUID {
        switch self {
        case .quest(let s): s.id
        case .routine(let s): s.id
        case .epic(let s): s.id
        }
    }

    /// What the row was paid, as stored; never recomputed.
    public var awardedPoints: Int {
        switch self {
        case .quest(let s): s.awardedPoints ?? 0
        case .routine(let s): s.awardedPoints ?? 0
        case .epic(let s): s.awardedPoints ?? 0
        }
    }

    fileprivate var title: String {
        switch self {
        case .quest(let s): s.title
        case .routine(let s): s.title
        case .epic(let s): s.title
        }
    }
}

/// Everything done on Today, most recently completed first: today's random quests (the hidden one
/// and a finished micro-action group included), the routines that left the Routines section as
/// done, and this week's epic. Skipped, replaced and cancelled rows are records, not
/// accomplishments, and routines done ahead stay in the Ahead section.
public struct CompletedStackState: Equatable, Sendable {
    public let items: [CompletedItem]
    public let totalPoints: Int

    public var count: Int { items.count }
    public var isEmpty: Bool { items.isEmpty }
    /// `4 done · +160`, the hand label of the section.
    public var summary: String { "\(count) done · +\(totalPoints)" }
    /// What VoiceOver says for the whole section; the view adds expanded or collapsed.
    public var accessibilityLabel: String { "Completed, \(count) done, \(totalPoints) coins" }

    /// - Parameters:
    ///   - quests: every `DailyQuest` the page's query holds; today's slots and the live epic are
    ///     picked out here, so the page and this rule cannot disagree on which is which.
    ///   - occurrences: every `RoutineOccurrence` the page's query holds.
    ///   - holding: rows that have just completed and are still showing it in their own section
    ///     (the check and the `+N` finish there); they join the stack once released.
    ///   - routineState: the page's builder for a routine row.
    public init(quests: [DailyQuest], occurrences: [RoutineOccurrence], today: String, tier: Tier, level: Int,
                holding: Set<UUID> = [], routineState: (RoutineOccurrence) -> RoutineRowState) {
        var found: [(at: Date?, item: CompletedItem)] = []

        for q in quests where q.dayKey == today && q.slot != .epic && !q.replaced {
            let state = QuestCardState(q, tier: tier)
            if state.isDone { found.append((q.completedAt, .quest(state))) }
        }
        if let epic = Epic.current(quests, on: today) {
            let state = EpicCardState(epic, today: today, tier: tier, level: level)
            if state.isDone { found.append((epic.completedAt, .epic(state))) }
        }
        // Due today (done ahead of time or not), or finished late today. Done ahead of its due day
        // stays under Ahead this week, which is not restyled.
        for o in occurrences where !o.isReplaced && !o.skipped
            && (o.dueDayKey == today || (o.completedDayKey == today && o.dueDayKey < today)) {
            let state = routineState(o)
            if state.isDone { found.append((o.completedAt, .routine(state))) }
        }

        let ordered = found.filter { !holding.contains($0.item.id) }.sorted { a, b in
            switch (a.at, b.at) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return (a.item.title, a.item.id.uuidString) < (b.item.title, b.item.id.uuidString)
            }
        }
        items = ordered.map(\.item)
        totalPoints = items.reduce(0) { $0 + $1.awardedPoints }
    }
}
