import Foundation
import SwiftData

/// Re-reading the body data for a day that is already on screen (`PLAN.md` §5).
///
/// The tier is fixed when the day is generated, but the day is generated the first time the app
/// is opened — which can be before the watch has synced last night's sleep, or before a period
/// was logged. So every foreground reads HealthKit again, and when the reading now says something
/// else the day can be re-planned.
///
/// **What is done is never touched.** Completed quests keep their text, their points and their
/// ledger entry; nothing is re-rolled, refunded or recomputed — the rule that an awarded value is
/// never recomputed holds here too. Only slots still open are redrawn, and open routines have
/// their downgrade decision made again. An open slot that is dropped is marked `replaced` rather
/// than deleted, the same as a slot an ad-hoc routine takes over: the row stays as the record
/// that it was once asked of you, and full-clear, streak and the calendar all skip it already.
public enum Replan {
    public struct Change: Equatable, Sendable {
        public var dayKey: String
        public var fromTier: Tier
        public var toTier: Tier
        /// Completed random quests, which stay exactly as they are.
        public var keptQuests: Int
        /// Open random quests that would be (or were) redrawn.
        public var redrawnQuests: Int
        /// Open routines whose light-version decision would be (or was) made again.
        public var adjustedRoutines: Int
    }

    /// What re-reading would change, or nil when it would change nothing — the day hasn't been
    /// generated yet, or the tier came out the same. Reads only; safe to call on every foreground.
    public static func preview(_ context: ModelContext, on dayKey: String, inputs: DayInputs,
                               in timeZone: TimeZone = .current) throws -> Change? {
        guard let day = try DayService.dailyContext(for: dayKey, in: context),
              day.tier != inputs.tier else { return nil }
        let regular = try DayService.quests(on: dayKey, in: context)
            .filter { !$0.isHiddenSlot && !$0.replaced && $0.slot != .epic }
        let openRoutines = try DayService.occurrences(dueOn: dayKey, in: context)
            .filter(Schedule.isOpen)
        return Change(dayKey: dayKey,
                      fromTier: day.tier,
                      toTier: inputs.tier,
                      keptQuests: regular.filter { $0.completedAt != nil }.count,
                      redrawnQuests: regular.filter { $0.completedAt == nil }.count,
                      adjustedRoutines: openRoutines.count)
    }

    /// Applies what `preview` describes. Returns the change, or nil when there was nothing to do.
    @discardableResult
    public static func apply(_ context: ModelContext, on dayKey: String, inputs: DayInputs,
                             in timeZone: TimeZone = .current,
                             rng: inout some RandomNumberGenerator) throws -> Change? {
        guard let change = try preview(context, on: dayKey, inputs: inputs, in: timeZone),
              let day = try DayService.dailyContext(for: dayKey, in: context) else { return nil }

        day.tier = inputs.tier
        day.onCycle = inputs.onCycle
        day.cycleDay = inputs.cycleDay
        day.energy = inputs.energy
        day.readiness = inputs.readiness
        day.hrv = inputs.hrv
        day.sleepHours = inputs.sleepHours
        day.restingHR = inputs.restingHR
        // The routine load is what it was: the same routines are still due today.
        day.randomSlots = Composition.slots(routineLoad: day.routineLoad)

        let quests = try DayService.quests(on: dayKey, in: context)
        let regular = quests.filter { !$0.isHiddenSlot && !$0.replaced && $0.slot != .epic }
        var completed = regular.filter { $0.completedAt != nil }
        for open in regular where open.completedAt == nil { open.replaced = true }

        // Slots the new tier asks for that a completed quest already answers are left alone —
        // an E that is done still fills the E slot. The rest are drawn fresh, skipping every
        // template the day has already served so nothing repeats inside one day.
        var plan = Composition.plan(tier: inputs.tier, slots: day.randomSlots, rng: &rng)
        for (index, slot) in plan.enumerated().reversed() {
            guard let match = completed.firstIndex(where: {
                $0.slot == slot.difficulty && $0.isTrivialGroup == slot.isTrivialGroup
            }) else { continue }
            completed.remove(at: match)
            plan.remove(at: index)
        }
        var drawn = Set(quests.compactMap(\.templateID) + quests.flatMap(\.trivialTemplateIDs))
        let weekKey = DayKey.weekKey(of: dayKey, in: timeZone) ?? ""
        try DayService.fill(context, plan: plan, on: dayKey, weekKey: weekKey,
                            excluding: &drawn, in: timeZone, rng: &rng)

        // Open routines: the light-version decision is made again for the tier the day now has.
        let routines = try context.fetch(FetchDescriptor<RoutineTask>())
        let byID = Dictionary(routines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for o in try DayService.occurrences(dueOn: dayKey, in: context) where Schedule.isOpen(o) {
            guard let routine = o.routineID.flatMap({ byID[$0] }) else { continue }
            if let light = Degrade.pick(for: routine, tier: inputs.tier, in: routines, rng: &rng) {
                o.degradedTextSnapshot = light.text
                o.degradedRoutineID = light.id
                o.degradedBasePoints = light.basePoints
                o.usedDegraded = true
            } else {
                o.degradedTextSnapshot = nil
                o.degradedRoutineID = nil
                o.degradedBasePoints = nil
                o.usedDegraded = false
            }
        }

        try context.save()
        return change
    }
}
