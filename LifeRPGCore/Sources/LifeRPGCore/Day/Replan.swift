import Foundation
import SwiftData

/// Re-reading the body data for a day that is already on screen (`PLAN.md` §5).
///
/// The tier is fixed when the day is generated, but the day is generated the first time the app
/// is opened — which can be before the watch has synced last night's sleep, or before a period
/// was logged. So every foreground reads HealthKit again, and when the reading now says something
/// else the day can be re-planned.
///
/// **A re-plan changes as little as it can.** What is done is never touched: completed quests keep
/// their text, their points and their ledger entry, and an awarded value is never recomputed. A
/// slot still open is kept too **as long as the new composition still asks for it** — a T group on
/// a cycle day stays a T group, and the E you were about to do stays that E. Only the slots the
/// new table no longer has are dropped, and only the slots it gained are drawn.
///
/// A dropped row is marked `replaced` (reason `.replan`) rather than deleted: the row stays as the
/// record that it was once asked of you, and full-clear, streak and the calendar all skip it.
public enum Replan {
    public struct Change: Equatable, Sendable {
        public var dayKey: String
        public var fromTier: Tier
        public var toTier: Tier
        /// Quests that stay exactly as they are — finished ones, and open ones the new
        /// composition still asks for.
        public var keptQuests: Int
        /// Open quests the new composition no longer has a slot for.
        public var droppedQuests: Int
        /// Slots the new composition gained, which would be drawn fresh.
        public var newQuests: Int
        /// Open routines whose light-version decision would actually flip.
        public var adjustedRoutines: Int
    }

    /// Does this quest answer a slot of that difficulty? A `.trivial` slot is the T group.
    static func answers(_ quest: DailyQuest, _ slot: Difficulty) -> Bool {
        slot == .trivial ? quest.isTrivialGroup : (quest.slot == slot && !quest.isTrivialGroup)
    }

    /// The whole decision, made from rows only so `preview` and `apply` cannot disagree:
    /// which open rows are dropped, and which slots are left to draw.
    ///
    /// Finished quests claim their slot first — they are staying whatever happens — then open ones
    /// in the order they were drawn. A finished quest the new table has no slot for is simply kept
    /// beside the day's slots; it is not dropped and does not consume one.
    static func split(plan: [Difficulty], quests: [DailyQuest])
        -> (kept: [DailyQuest], dropped: [DailyQuest], toDraw: [Difficulty]) {
        var slots = plan
        var kept: [DailyQuest] = []
        var dropped: [DailyQuest] = []

        func claim(_ quest: DailyQuest) -> Bool {
            guard let i = slots.firstIndex(where: { answers(quest, $0) }) else { return false }
            slots.remove(at: i)
            kept.append(quest)
            return true
        }

        let completed = quests.filter { $0.completedAt != nil }
        let open = quests.filter { $0.completedAt == nil }
        for quest in completed where !claim(quest) { kept.append(quest) }
        for quest in open where !claim(quest) { dropped.append(quest) }
        return (kept, dropped, slots)
    }

    /// Whether this routine's light-version decision would change under `tier`.
    static func wouldFlip(_ occurrence: RoutineOccurrence, routine: RoutineTask?,
                          tier: Tier, in routines: [RoutineTask]) -> Bool {
        guard let routine else { return false }
        let offered = tier.isLow && !Degrade.versions(of: routine, in: routines).isEmpty
        return offered != occurrence.usedDegraded
    }

    /// What re-reading would change, or nil when it would change nothing visible — the day hasn't
    /// been generated yet, the tier came out the same, or the new tier asks for exactly what is
    /// already on the page. Reads only; safe to call on every foreground.
    public static func preview(_ context: ModelContext, on dayKey: String, inputs: DayInputs,
                               in timeZone: TimeZone = .current) throws -> Change? {
        guard let day = try DayService.dailyContext(for: dayKey, in: context),
              day.tier != inputs.tier else { return nil }

        let regular = try DayService.quests(on: dayKey, in: context)
            .filter { !$0.isHiddenSlot && !$0.replaced && $0.slot != .epic }
        let plan = Composition.plan(tier: inputs.tier,
                                    slots: Composition.slots(routineLoad: day.routineLoad))
        let (kept, dropped, toDraw) = split(plan: plan, quests: regular)

        let routines = try context.fetch(FetchDescriptor<RoutineTask>())
        let byID = Dictionary(routines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let flips = try DayService.occurrences(dueOn: dayKey, in: context)
            .filter(Schedule.isOpen)
            .filter { wouldFlip($0, routine: $0.routineID.flatMap { byID[$0] },
                                tier: inputs.tier, in: routines) }

        // The tier moved but the page would look exactly the same — low and veryLow ask for the
        // same thing on a squeezed day, and they score the same. Not worth a prompt.
        guard !dropped.isEmpty || !toDraw.isEmpty || !flips.isEmpty else { return nil }

        return Change(dayKey: dayKey, fromTier: day.tier, toTier: inputs.tier,
                      keptQuests: kept.count, droppedQuests: dropped.count,
                      newQuests: toDraw.count, adjustedRoutines: flips.count)
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
        let plan = Composition.plan(tier: inputs.tier, slots: day.randomSlots)
        let (_, dropped, toDraw) = split(plan: plan, quests: regular)

        for quest in dropped {
            quest.replaced = true
            quest.replacedReason = .replan
        }
        // Nothing the day has already served is drawn again, so a re-plan can't repeat a quest.
        var drawn = Set(quests.compactMap(\.templateID) + quests.flatMap(\.trivialTemplateIDs))
        let weekKey = DayKey.weekKey(of: dayKey, in: timeZone) ?? ""
        try DayService.fill(context, plan: toDraw, on: dayKey, weekKey: weekKey,
                            excluding: &drawn, in: timeZone, rng: &rng)

        // Open routines: the light-version decision is made again for the tier the day now has.
        // Only the ones that would actually flip are touched, so a version already chosen by hand
        // on a day whose tier didn't cross the low line is left alone.
        let routines = try context.fetch(FetchDescriptor<RoutineTask>())
        let byID = Dictionary(routines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for o in try DayService.occurrences(dueOn: dayKey, in: context) where Schedule.isOpen(o) {
            let routine = o.routineID.flatMap { byID[$0] }
            guard let routine, wouldFlip(o, routine: routine, tier: inputs.tier, in: routines) else { continue }
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
