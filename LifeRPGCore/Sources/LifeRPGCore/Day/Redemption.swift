import Foundation
import SwiftData

/// Spending coins on something other than a reroll or an epic extension (`PLAN.md` §6):
/// cancelling a quest or a routine, a streak freeze, and real-world rewards.
///
/// Every purchase obeys the one balance rule in `Purchase.blocked`, writes one negative ledger
/// entry and is final. Nothing here deletes a row: a cancelled quest stays as history, marked
/// `replaced(.cancelled)`; a cancelled routine is closed as `skipped`, the ledger entry being what
/// tells "paid to drop it" from "gave up".
public enum Redemption {
    // MARK: prices — `PLAN.md` §6 "Virtual rewards", noticeably above what the quest itself pays

    public static let cancelRoutineCost = 200
    /// The level-1 price. What a freeze actually costs is `freezeCost(covering:level:ledger:)`.
    public static let streakFreezeCost = 300

    /// E 120, M 250, H 450. Nil for anything else: T, hidden and epic can't be cancelled.
    public static func cancelCost(for slot: Difficulty) -> Int? {
        switch slot {
        case .easy: 120
        case .medium: 250
        case .hard: 450
        case .trivial, .epic: nil
        }
    }

    // MARK: cancelling a quest

    /// Today's regular E / M / H slot, still open. The hidden quest is a reward, not an ask; the
    /// epic already costs nothing to leave undone.
    public static func blocked(cancelling quest: DailyQuest, on dayKey: String, balance: Int) -> Purchase.Blocked? {
        if quest.completedAt != nil { return .alreadyCompleted }
        guard quest.dayKey == dayKey, !quest.isHiddenSlot, !quest.replaced, !quest.isTrivialGroup,
              let cost = cancelCost(for: quest.slot) else { return .notAvailable }
        return Purchase.blocked(cost: cost, balance: balance)
    }

    /// The slot stops gating the full clear, earns nothing and doesn't count toward the streak.
    public static func cancel(_ quest: DailyQuest, on dayKey: String, in context: ModelContext,
                              now: Date = Date()) throws {
        if let b = blocked(cancelling: quest, on: dayKey, balance: try Economy.balance(context)) { throw b }
        let cost = cancelCost(for: quest.slot)!
        quest.replaced = true
        quest.replacedReason = .cancelled
        let entry = Economy.record(context, kind: .redeem, points: -cost, dayKey: dayKey,
                                   refID: quest.id, note: "Cancel \(quest.slot.code): \(quest.textSnapshot)",
                                   now: now)
        do {
            try context.save()
        } catch {
            quest.replaced = false
            quest.replacedReasonRaw = nil
            context.delete(entry)
            throw error
        }
    }

    // MARK: cancelling a routine

    /// An open fixed routine on today's page — due today or overdue — that gates the clear.
    ///
    /// Not a flexible one: it can already be moved within the week for free, and Sunday's
    /// settlement would count the cancelled session as missing. Not a `countsForClear = false`
    /// one: it is never charged and never gates anything, so there is nothing to buy off.
    public static func blocked(cancelling o: RoutineOccurrence, flexible: Bool, on dayKey: String,
                               balance: Int) -> Purchase.Blocked? {
        if o.completedDayKey != nil { return .alreadyCompleted }
        guard !o.skipped, !flexible, o.countsForClear, o.dueDayKey <= dayKey else { return .notAvailable }
        return Purchase.blocked(cost: cancelRoutineCost, balance: balance)
    }

    /// Closes the occurrence: no further overdue deductions, and the day's clear no longer waits
    /// on it. Deductions already charged on earlier days stay.
    public static func cancel(_ o: RoutineOccurrence, flexible: Bool, on dayKey: String,
                              in context: ModelContext, now: Date = Date()) throws {
        if let b = blocked(cancelling: o, flexible: flexible, on: dayKey,
                           balance: try Economy.balance(context)) { throw b }
        o.skipped = true
        let entry = Economy.record(context, kind: .redeem, points: -cancelRoutineCost, dayKey: dayKey,
                                   refID: o.id, note: "Cancel routine: \(o.displayText)", now: now)
        do {
            try context.save()
        } catch {
            o.skipped = false
            context.delete(entry)
            throw error
        }
    }

    // MARK: streak freeze

    /// Why a freeze can't be bought today, or nil. Bought after the break (decided with the user),
    /// so there has to be a missed day to cover — `Streak.repairableDay`.
    /// `cost` is `freezeCost` for the day it would cover; the default is the level-1 price.
    public static func blockedFreeze(days: Set<String>, frozen: Set<String>, today: String,
                                     balance: Int, cost: Int = streakFreezeCost,
                                     in timeZone: TimeZone = .current) -> Purchase.Blocked? {
        guard Streak.repairableDay(days: days, frozen: frozen, today: today, in: timeZone) != nil else {
            return .nothingToRepair
        }
        return Purchase.blocked(cost: cost, balance: balance)
    }

    /// What covering `gap` costs: 0 when the level has a monthly free freeze and no free one has
    /// yet covered a day in `gap`'s calendar month, otherwise `Perks.freezeCost` (300, 150 from
    /// Lv 20). A free freeze is a 0-point `freeze` entry, and its `dayKey` is the day it covered.
    public static func freezeCost(covering gap: String, level: Int, ledger: [LedgerEntry]) -> Int {
        let month = gap.prefix(7)                                     // "2026-09"
        let freeUsed = ledger.filter {
            $0.kind == Economy.Kind.freeze.rawValue && $0.points == 0 && $0.dayKey.prefix(7) == month
        }.count
        return freeUsed < Perks.monthlyFreeFreezes(level: level) ? 0 : Perks.freezeCost(level: level)
    }

    /// Covers the missed day and returns it. The entry is booked **to that day**, which is how the
    /// streak finds it; `timestamp` records when it was bought.
    @discardableResult
    public static func freeze(on today: String, in context: ModelContext,
                              timeZone: TimeZone = .current, now: Date = Date()) throws -> String {
        let days = try Streak.completedDayKeys(context)
        let frozen = try Streak.frozenDayKeys(context)
        let ledger = try context.fetch(FetchDescriptor<LedgerEntry>())
        guard let gap = Streak.repairableDay(days: days, frozen: frozen, today: today, in: timeZone) else {
            throw Purchase.Blocked.nothingToRepair
        }
        let cost = freezeCost(covering: gap, level: Economy.level(ledger), ledger: ledger)
        if let b = blockedFreeze(days: days, frozen: frozen, today: today,
                                 balance: Economy.balance(ledger), cost: cost, in: timeZone) { throw b }
        let entry = Economy.record(context, kind: .freeze, points: -cost, dayKey: gap,
                                   note: cost == 0 ? "Streak freeze (free this month)" : "Streak freeze",
                                   now: now)
        do {
            try context.save()
        } catch {
            context.delete(entry)
            throw error
        }
        // Joining two runs can put the whole past a milestone neither side reached. Like after a
        // completion, a failure here leaves it due for the next settle rather than undoing the freeze.
        _ = try? StreakMilestone.settle(context, today: today, in: timeZone, now: now)
        return gap
    }

    // MARK: real-world rewards

    public static func blocked(redeeming reward: Reward, balance: Int) -> Purchase.Blocked? {
        guard reward.isActive else { return .notAvailable }
        return Purchase.blocked(cost: RewardPricing.coins(for: reward), balance: balance)
    }

    /// One `redeem` entry at today's price; the reward row itself doesn't change, so repricing it
    /// later leaves this redemption at what it cost.
    public static func redeem(_ reward: Reward, on dayKey: String, in context: ModelContext,
                              now: Date = Date()) throws {
        if let b = blocked(redeeming: reward, balance: try Economy.balance(context)) { throw b }
        let entry = Economy.record(context, kind: .redeem, points: -RewardPricing.coins(for: reward),
                                   dayKey: dayKey, refID: reward.id, note: reward.name, now: now)
        let wasGoal = reward.isGoal
        reward.isGoal = false                     // reached — the goal line has nothing left to show
        do {
            try context.save()
        } catch {
            reward.isGoal = wasGoal
            context.delete(entry)
            throw error
        }
    }

    /// Archived rather than deleted — it may already have been redeemed. An archived reward can't
    /// stay the savings goal.
    public static func archive(_ reward: Reward, in context: ModelContext) throws {
        let (active, goal) = (reward.isActive, reward.isGoal)
        reward.isActive = false
        reward.isGoal = false
        do {
            try context.save()
        } catch {
            reward.isActive = active
            reward.isGoal = goal
            throw error
        }
    }
}
