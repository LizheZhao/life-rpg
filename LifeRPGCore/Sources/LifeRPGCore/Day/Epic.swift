import Foundation
import SwiftData

/// The weekly epic (`PLAN.md` §3 "Epic").
///
/// Drawn on the first day of an ISO week the app generates — Monday, or whichever day the app is
/// first opened that week — and valid through Sunday. It sits outside the composition table: it
/// takes no random slot, doesn't gate the full clear and isn't penalized when it runs out.
///
/// **At most one epic is live at a time.** Extending it (50, at most twice) pushes its last day a
/// week further, and the week it spills into gets no epic of its own. An epic that runs out
/// unfinished simply stays in history with `completedAt == nil`.
///
/// The row keeps the `dayKey` / `weekKey` of the day it was drawn. Which week it *counts for* on
/// the calendar is the week it was completed in (`CalendarMarks.epicWeeks`), not its `weekKey`.
public enum Epic {
    /// Twice, three times from Lv 5 — `Perks.epicMaxExtensions`.
    public static func maxExtensions(level: Int) -> Int { Perks.epicMaxExtensions(level: level) }
    /// `PLAN.md` §6 "Virtual rewards": extend epic by a week. Deliberately **below** what an epic
    /// pays (60–150): extending doesn't get you out of any work — you still have to do it — it only
    /// buys time, so pricing it above the payout made letting it lapse always the better deal.
    public static let extensionCost = 50

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notAnEpic
        case alreadyCompleted
        case expired(lastDayKey: String)
        case maxExtensions
        case blocked(Purchase.Blocked)
        /// Replacing: an extended epic stays what it is, same as for a reroll.
        case extended
        /// Replacing with the epic that is already there.
        case sameEpic
        case emptyText

        public var description: String {
            switch self {
            case .notAnEpic: "not an epic"
            case .alreadyCompleted: "already completed"
            case .expired(let last): "ran out on \(last)"
            case .maxExtensions: "already extended as many times as allowed"
            case .blocked(let b): b.description
            case .extended: "an extended epic can't be swapped"
            case .sameEpic: "that one is already this week's epic"
            case .emptyText: "the epic needs a description"
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
    public static func blocked(_ epic: DailyQuest, on dayKey: String, balance: Int, level: Int = 1,
                               in timeZone: TimeZone = .current) -> Failure? {
        guard epic.slot == .epic, !epic.replaced else { return .notAnEpic }
        if epic.completedAt != nil { return .alreadyCompleted }
        if let last = lastDayKey(of: epic, in: timeZone), dayKey > last { return .expired(lastDayKey: last) }
        if epic.extensionCount >= maxExtensions(level: level) { return .maxExtensions }
        if let b = Purchase.blocked(cost: extensionCost, balance: balance) {
            return .blocked(b)
        }
        return nil
    }

    /// Spends 50 to push `epic` a week further. The ledger entry is booked to `dayKey`, the day
    /// the coins were spent.
    public static func extend(_ epic: DailyQuest, on dayKey: String, in context: ModelContext,
                              timeZone: TimeZone = .current, now: Date = Date()) throws {
        if let failure = blocked(epic, on: dayKey, balance: try Economy.balance(context),
                                 level: try Economy.level(context), in: timeZone) {
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

    // MARK: replacing by hand

    /// What the week's epic can be swapped for (`PLAN.md` §3 "Epic").
    public enum Pick {
        /// One from the library, chosen rather than drawn.
        case template(QuestTemplate)
        /// Written on the spot. It has no template, so it pays an ordinary epic roll (60–150) and
        /// starts no cooldown.
        case custom(text: String)
    }

    /// The library epics `epic` can be swapped for: every active one but itself, cooldown or not —
    /// picking by hand is the point.
    public static func replaceCandidates(_ templates: [QuestTemplate],
                                         replacing epic: DailyQuest) -> [QuestTemplate] {
        templates.filter { $0.isActive && $0.difficulty == .epic && $0.id != epic.templateID }
            .sorted { $0.text < $1.text }
    }

    /// Why `epic` can't be swapped on `dayKey`, or nil. No balance check: it is free.
    public static func blockedReplace(_ epic: DailyQuest, on dayKey: String,
                                      in timeZone: TimeZone = .current) -> Failure? {
        guard epic.slot == .epic, !epic.replaced else { return .notAnEpic }
        if epic.completedAt != nil { return .alreadyCompleted }
        if let last = lastDayKey(of: epic, in: timeZone), dayKey > last { return .expired(lastDayKey: last) }
        if epic.extensionCount > 0 { return .extended }
        return nil
    }

    /// Swaps the live epic for `pick`, free. The old row stays as history, marked
    /// `replaced(.swapped)`; the new one keeps its `dayKey` / `weekKey` — so the same deadline —
    /// and its `rerollCount`, so a later reroll still reads as the same week's slot.
    @discardableResult
    public static func replace(_ epic: DailyQuest, with pick: Pick, on dayKey: String,
                               in context: ModelContext,
                               timeZone: TimeZone = .current) throws -> DailyQuest {
        if let failure = blockedReplace(epic, on: dayKey, in: timeZone) { throw failure }
        let fresh: DailyQuest
        var served: (QuestTemplate, String?)?
        switch pick {
        case .template(let template):
            guard template.id != epic.templateID else { throw Failure.sameEpic }
            fresh = DailyQuest(template: template, slot: .epic, dayKey: epic.dayKey, weekKey: epic.weekKey)
            served = (template, template.lastServedDayKey)
            template.lastServedDayKey = dayKey
        case .custom(let text):
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw Failure.emptyText }
            fresh = DailyQuest()
            fresh.dayKey = epic.dayKey
            fresh.weekKey = epic.weekKey
            fresh.slot = .epic
            fresh.textSnapshot = text
        }
        fresh.rerollCount = epic.rerollCount
        context.insert(fresh)
        epic.replaced = true
        epic.replacedReason = .swapped
        do {
            try context.save()
        } catch {
            epic.replaced = false
            epic.replacedReasonRaw = nil
            if let (template, before) = served { template.lastServedDayKey = before }
            context.delete(fresh)
            throw error
        }
        return fresh
    }
}
