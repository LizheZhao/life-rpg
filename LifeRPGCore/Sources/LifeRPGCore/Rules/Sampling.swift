import Foundation
import SwiftData

/// Drawing a template into a slot: cooldown and weekend filtering, affinity weighting.
///
/// How hard a day's draw is comes from the composition table alone (`Composition.table`), which is
/// what a low tier moves — there is no second difficulty-like axis to filter on.
public enum Sampling {
    /// `PLAN.md` §3. Cooldown counts from the **completion** day; a quest that was only drawn
    /// (or rerolled away) gets a flat 1 day so it can't reappear tomorrow.
    ///
    /// "Cooldown N days" means: last key on D → ineligible D+1 … D+N, eligible again from D+N+1.
    /// A key in the future (clock moved back) is treated as still cooling down.
    public static func inCooldown(_ t: QuestTemplate, today: String,
                                  in timeZone: TimeZone = .current) -> Bool {
        if let done = t.lastCompletedDayKey,
           let gap = DayKey.daysBetween(done, today, in: timeZone),
           gap <= t.effectiveCooldownDays { return true }
        if let served = t.lastServedDayKey,
           let gap = DayKey.daysBetween(served, today, in: timeZone),
           gap <= 1 { return true }
        return false
    }

    /// Everything that may be drawn into one slot today.
    public static func eligible(_ templates: [QuestTemplate],
                                difficulty: Difficulty,
                                dayKey: String,
                                excluding excluded: Set<UUID> = [],
                                in timeZone: TimeZone = .current) -> [QuestTemplate] {
        let isWeekend = DayKey.isWeekend(dayKey, in: timeZone)
        return templates.filter { t in
            t.isActive
                && t.difficulty == difficulty
                && (!t.weekendOnly || isWeekend)        // weekend_only is out of the pool Mon–Fri
                && !excluded.contains(t.id)
                && !inCooldown(t, today: dayKey, in: timeZone)
        }
    }

    /// The hidden pool: same filters, but `hiddenEligible` instead of a difficulty.
    public static func eligibleHidden(_ templates: [QuestTemplate],
                                      dayKey: String,
                                      excluding excluded: Set<UUID> = [],
                                      in timeZone: TimeZone = .current) -> [QuestTemplate] {
        let isWeekend = DayKey.isWeekend(dayKey, in: timeZone)
        return templates.filter { t in
            t.isActive
                && t.hiddenEligible
                && (!t.weekendOnly || isWeekend)
                && !excluded.contains(t.id)
                && !inCooldown(t, today: dayKey, in: timeZone)
        }
    }

    /// Affinity weight: -2 → 1, 0 → 3, +2 → 5. Disliked entries are downweighted, never removed.
    public static func weight(_ t: QuestTemplate) -> Int {
        max(1, 3 + t.affinity)
    }

    /// One weighted draw. Nil when the pool is empty — the slot then simply stays unfilled.
    public static func pick(from pool: [QuestTemplate],
                            rng: inout some RandomNumberGenerator) -> QuestTemplate? {
        let total = pool.reduce(0) { $0 + weight($1) }
        guard total > 0 else { return nil }
        var roll = Int.random(in: 0..<total, using: &rng)
        for t in pool {
            roll -= weight(t)
            if roll < 0 { return t }
        }
        return pool.last
    }

    /// `n` distinct draws, each weighted. Returns fewer than `n` only when the pool runs out.
    public static func pickDistinct(_ n: Int, from pool: [QuestTemplate],
                                    rng: inout some RandomNumberGenerator) -> [QuestTemplate] {
        var remaining = pool
        var out: [QuestTemplate] = []
        while out.count < n, let next = pick(from: remaining, rng: &rng) {
            out.append(next)
            remaining.removeAll { $0.id == next.id }
        }
        return out
    }

    /// One value from a parameterized template's `variants` (`PLAN.md` "Parameterized templates"),
    /// or nil when the template has none. Drawn at generation time and snapshotted onto the
    /// `DailyQuest`, so history keeps the value you actually got rather than re-rolling it.
    public static func variant(of t: QuestTemplate, rng: inout some RandomNumberGenerator) -> String? {
        t.variants.isEmpty ? nil : t.variants.randomElement(using: &rng)
    }

    /// Fetches the active templates once; `ensureToday` filters the same array per slot rather
    /// than issuing one fetch per slot.
    public static func activeTemplates(_ context: ModelContext) throws -> [QuestTemplate] {
        try context.fetch(FetchDescriptor<QuestTemplate>(predicate: #Predicate { $0.isActive }))
    }
}
