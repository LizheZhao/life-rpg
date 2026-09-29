import Foundation
import SwiftData

/// Paying to swap a random slot — or the week's epic — for a different draw (`PLAN.md` §6).
///
/// **The old row is kept.** It is marked `replaced` with reason `.rerolled`, and the replacement is
/// a new row carrying `rerollCount + 1`. `DailyQuest` is the history the calendar, day detail and
/// summary read, so overwriting it in place would erase what was swapped away. Everything that
/// already skips `replaced` rows (full clear, streak, calendar dots, ad-hoc, re-plan, auto-verify)
/// skips a rerolled-away one for free.
public enum Reroll {
    /// `base × 1.5^n`, rounded **up**, where `n` is how many times this slot has already been
    /// rerolled today. Bases are T 5, E 10, M 20, H 30, EPIC 80.
    ///
    /// So E goes 10 / 15 / 23 / 34 and H goes 30 / 45 / 68 / 102 — the escalation is what stops a
    /// reroll from being a free "give me something easier" button. It resets daily because the
    /// count lives on the day's row, not on the template.
    public static func cost(base: Int, rerollCount: Int) -> Int {
        Int((Double(base) * pow(1.5, Double(max(0, rerollCount)))).rounded(.up))
    }

    /// The epic is a flat 80 every time (`PLAN.md` §6) — it doesn't escalate — and 40 from Lv 12.
    /// A regular slot costs 0 while the day's free rerolls (`Perks.freeRerollsPerDay`) aren't used
    /// up; `freeUsedToday` is `freeRerollsUsed` for the day. The defaults are a level-1 player.
    public static func cost(for quest: DailyQuest, level: Int = 1, freeUsedToday: Int = 0) -> Int {
        if quest.slot == .epic { return Perks.epicRerollCost(level: level) }
        if freeUsedToday < Perks.freeRerollsPerDay(level: level) { return 0 }
        return cost(base: quest.slot.rerollBase, rerollCount: quest.rerollCount)
    }

    /// Free rerolls already taken on `dayKey`: its 0-point `reroll` entries. An epic reroll never
    /// costs 0, so these are all regular-slot ones.
    public static func freeRerollsUsed(_ ledger: [LedgerEntry], on dayKey: String) -> Int {
        ledger.filter { $0.kind == Economy.Kind.reroll.rawValue && $0.dayKey == dayKey && $0.points == 0 }.count
    }

    public static func freeRerollsUsed(_ context: ModelContext, on dayKey: String) throws -> Int {
        let kind = Economy.Kind.reroll.rawValue
        return freeRerollsUsed(try context.fetch(FetchDescriptor<LedgerEntry>(
            predicate: #Predicate { $0.kind == kind && $0.dayKey == dayKey })), on: dayKey)
    }

    /// The balance rule: a reroll can never take you below zero, and you can't reroll while already
    /// there (`PLAN.md` §6). Spending down to exactly zero is allowed — that is not debt.
    ///
    /// Penalties are the only thing that may push the balance negative, because they are something
    /// that happens *to* you; a purchase you chose to make should not.
    public static func blocked(cost: Int, balance: Int, completed: Bool) -> Purchase.Blocked? {
        if completed { return .alreadyCompleted }
        return Purchase.blocked(cost: cost, balance: balance)
    }

    /// Whether `quest` may be rerolled on `dayKey` at all, then whether it is affordable.
    /// A regular slot (T group included) only on its own day; the epic on any day it is live,
    /// until it is extended.
    /// The hidden quest is the reward for a cleared day, not a slot, and is never rerolled.
    public static func blocked(for quest: DailyQuest, on dayKey: String, balance: Int,
                               level: Int = 1, freeUsedToday: Int = 0,
                               in timeZone: TimeZone = .current) -> Purchase.Blocked? {
        if quest.completedAt != nil { return .alreadyCompleted }
        if quest.slot == .epic {
            guard Epic.covers(quest, dayKey, in: timeZone) else { return .notAvailable }
            if quest.extensionCount > 0 { return .epicExtended }
        } else {
            guard quest.dayKey == dayKey, !quest.isHiddenSlot, !quest.replaced else { return .notAvailable }
        }
        return blocked(cost: cost(for: quest, level: level, freeUsedToday: freeUsedToday),
                       balance: balance, completed: false)
    }

    /// Swaps `quest` for a fresh draw of the same slot and charges for it. Returns the new row.
    ///
    /// Nothing the day has already served is drawn again — including what earlier rerolls swapped
    /// away — so a reroll can't bounce between two quests. When the pool has nothing else, the
    /// reroll is refused and nothing is charged. The spend is booked to `dayKey`, the day it
    /// happened, which for the epic is not the day it was drawn.
    @discardableResult
    public static func perform(_ quest: DailyQuest, on dayKey: String, in context: ModelContext,
                               timeZone: TimeZone = .current, now: Date = Date(),
                               rng: inout some RandomNumberGenerator) throws -> DailyQuest {
        let level = try Economy.level(context)
        let freeUsed = try freeRerollsUsed(context, on: dayKey)
        if let b = blocked(for: quest, on: dayKey, balance: try Economy.balance(context),
                           level: level, freeUsedToday: freeUsed, in: timeZone) {
            throw b
        }
        let price = cost(for: quest, level: level, freeUsedToday: freeUsed)

        let fresh: DailyQuest?
        if quest.slot == .epic {
            let epicRaw = Difficulty.epic.rawValue
            let seen = try context.fetch(FetchDescriptor<DailyQuest>(
                predicate: #Predicate { $0.slotRaw == epicRaw }))
                .filter { $0.dayKey == quest.dayKey }.compactMap(\.templateID)
            fresh = try Epic.draw(context, on: quest.dayKey, weekKey: quest.weekKey, servedOn: dayKey,
                                  avoiding: Set(seen), strict: true, in: timeZone, rng: &rng)
            // Same `dayKey`, so the same deadline. Never extended: `blocked` refuses that.
        } else {
            let today = try DayService.quests(on: dayKey, in: context)
            var drawn = Set(today.compactMap(\.templateID) + today.flatMap(\.trivialTemplateIDs))
            fresh = try DayService.fill(context, plan: [quest.slot], on: dayKey, weekKey: quest.weekKey,
                                        excluding: &drawn, in: timeZone, rng: &rng).first
        }
        guard let fresh else { throw Purchase.Blocked.noCandidates }

        fresh.rerollCount = quest.rerollCount + 1
        quest.replaced = true
        quest.replacedReason = .rerolled
        let entry = Economy.record(context, kind: .reroll, points: -price, dayKey: dayKey,
                                   refID: quest.id, note: "Reroll: \(quest.textSnapshot)", now: now)
        do {
            try context.save()
        } catch {
            // Same rule as completion: nothing happened until it is on disk.
            quest.replaced = false
            quest.replacedReasonRaw = nil
            context.delete(fresh)
            context.delete(entry)
            throw error
        }
        return fresh
    }
}
