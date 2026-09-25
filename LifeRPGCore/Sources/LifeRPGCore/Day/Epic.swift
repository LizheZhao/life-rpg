import Foundation
import SwiftData

/// The weekly epic (`PLAN.md` §3 "Epic").
///
/// Drawn on the first day of an ISO week the app generates — Monday, or whichever day the app is
/// first opened that week — and valid through Sunday. It sits outside the composition table: it
/// takes no random slot, doesn't gate the full clear and isn't penalized when it runs out.
///
/// **At most one epic is live at a time.** Extending it (400, at most twice) pushes its last day a
/// week further, and the week it spills into gets no epic of its own. An epic that runs out
/// unfinished simply stays in history with `completedAt == nil`.
///
/// The row keeps the `dayKey` / `weekKey` of the day it was drawn. Which week it *counts for* on
/// the calendar is the week it was completed in (`CalendarMarks.epicWeeks`), not its `weekKey`.
public enum Epic {
    public static let maxExtensions = 2
    /// `PLAN.md` §6 "Virtual rewards": extend epic by a week.
    public static let extensionCost = 400

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notAnEpic
        case alreadyCompleted
        case expired(lastDayKey: String)
        case maxExtensions
        case blocked(Reroll.Blocked)

        public var description: String {
            switch self {
            case .notAnEpic: "not an epic"
            case .alreadyCompleted: "already completed"
            case .expired(let last): "ran out on \(last)"
            case .maxExtensions: "already extended \(Epic.maxExtensions) times"
            case .blocked(let b): b.description
            }
        }
    }

    /// The last day `epic` can be done: the Sunday of the week it was drawn in, plus a week per
    /// extension. Nil only for a malformed `dayKey`.
    public static func lastDayKey(of epic: DailyQuest, in timeZone: TimeZone = .current) -> String? {
        guard let weekday = DayKey.weekday(of: epic.dayKey, in: timeZone) else { return nil }
        let toSunday = weekday == .sunday ? 0 : 8 - weekday.rawValue    // ISO weeks end on Sunday
        return DayKey.adding(toSunday + 7 * epic.extensionCount, to: epic.dayKey, in: timeZone)
    }

    /// Whether `epic` is still on the page on `dayKey`, done or not.
    public static func covers(_ epic: DailyQuest, _ dayKey: String,
                              in timeZone: TimeZone = .current) -> Bool {
        guard epic.slot == .epic, !epic.replaced,
              let last = lastDayKey(of: epic, in: timeZone) else { return false }
        return epic.dayKey <= dayKey && dayKey <= last
    }

    /// The epic live on `dayKey`, from rows the caller already holds. A completed epic still
    /// counts until it runs out — that is what keeps a second one from being drawn the same week.
    public static func current(_ quests: [DailyQuest], on dayKey: String,
                               in timeZone: TimeZone = .current) -> DailyQuest? {
        quests.filter { covers($0, dayKey, in: timeZone) }.max { $0.dayKey < $1.dayKey }
    }

    public static func current(on dayKey: String, in context: ModelContext,
                               timeZone: TimeZone = .current) throws -> DailyQuest? {
        let epic = Difficulty.epic.rawValue
        let rows = try context.fetch(FetchDescriptor<DailyQuest>(
            predicate: #Predicate { $0.slotRaw == epic }))
        return current(rows, on: dayKey, in: timeZone)
    }

    /// Draws this week's epic if none is live on `dayKey`. Idempotent: once drawn (or while an
    /// extended one is still running) it returns nil. The epic drawn most recently is left out of
    /// the pool so the same one doesn't come round two weeks running — unless it is the only one.
    @discardableResult
    static func ensure(_ context: ModelContext, on dayKey: String, weekKey: String,
                       in timeZone: TimeZone = .current,
                       rng: inout some RandomNumberGenerator) throws -> DailyQuest? {
        let epicRaw = Difficulty.epic.rawValue
        let rows = try context.fetch(FetchDescriptor<DailyQuest>(
            predicate: #Predicate { $0.slotRaw == epicRaw }))
        guard current(rows, on: dayKey, in: timeZone) == nil else { return nil }

        let previous = rows.filter { $0.dayKey < dayKey }.max { $0.dayKey < $1.dayKey }?.templateID
        return try draw(context, on: dayKey, weekKey: weekKey, servedOn: dayKey,
                        avoiding: previous.map { [$0] } ?? [], in: timeZone, rng: &rng)
    }

    /// One epic row. `avoiding` is dropped from the pool while anything else is left (`strict`
    /// makes it a hard exclusion — a reroll must never hand back the epic it just swapped away).
    /// `dayKey` is the row's own key, which fixes its window; `servedOn` is today, for cooldown.
    static func draw(_ context: ModelContext, on dayKey: String, weekKey: String, servedOn: String,
                     avoiding: Set<UUID>, strict: Bool = false,
                     in timeZone: TimeZone = .current,
                     rng: inout some RandomNumberGenerator) throws -> DailyQuest? {
        let templates = try Sampling.activeTemplates(context)
        var pool = Sampling.eligible(templates, difficulty: .epic, dayKey: servedOn, in: timeZone)
        let others = pool.filter { !avoiding.contains($0.id) }
        if strict || !others.isEmpty { pool = others }
        guard let template = Sampling.pick(from: pool, rng: &rng) else { return nil }

        let quest = DailyQuest(template: template, slot: .epic, dayKey: dayKey, weekKey: weekKey,
                               variant: Sampling.variant(of: template, rng: &rng))
        context.insert(quest)
        template.lastServedDayKey = servedOn
        return quest
    }

    /// Why `epic` can't be extended on `dayKey`, or nil when it can. Same balance rule as a reroll:
    /// a purchase may spend down to exactly zero, never below, and never while already in debt.
    public static func blocked(_ epic: DailyQuest, on dayKey: String, balance: Int,
                               in timeZone: TimeZone = .current) -> Failure? {
        guard epic.slot == .epic, !epic.replaced else { return .notAnEpic }
        if epic.completedAt != nil { return .alreadyCompleted }
        if let last = lastDayKey(of: epic, in: timeZone), dayKey > last { return .expired(lastDayKey: last) }
        if epic.extensionCount >= maxExtensions { return .maxExtensions }
        if let b = Reroll.blocked(cost: extensionCost, balance: balance, completed: false) {
            return .blocked(b)
        }
        return nil
    }

    /// Spends 400 to push `epic` a week further. The ledger entry is booked to `dayKey`, the day
    /// the coins were spent.
    public static func extend(_ epic: DailyQuest, on dayKey: String, in context: ModelContext,
                              timeZone: TimeZone = .current, now: Date = Date()) throws {
        if let failure = blocked(epic, on: dayKey, balance: try Economy.balance(context), in: timeZone) {
            throw failure
        }
        epic.extensionCount += 1
        let entry = Economy.record(context, kind: .redeem, points: -extensionCost, dayKey: dayKey,
                                   refID: epic.id, note: "Extend epic: \(epic.textSnapshot)", now: now)
        do {
            try context.save()
        } catch {
            epic.extensionCount -= 1
            context.delete(entry)
            throw error
        }
    }
}
