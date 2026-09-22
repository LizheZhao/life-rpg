import Foundation
import SwiftData

/// The per-day inputs `ensureToday` needs but cannot measure itself.
///
/// Stage 3 fills `tier` / `onCycle` / `energy` / `readiness` from HealthKit; until then the
/// defaults stand in, which is why they are a parameter rather than something `ensureToday`
/// decides. Routine load is **not** here: it is counted from the occurrences `ensureToday`
/// schedules, so the number that sizes the random slots and the routines on the page can't disagree.
public struct DayInputs: Equatable, Sendable {
    public var tier: Tier
    public var onCycle: Bool
    public var energy: Double
    public var readiness: Int

    public init(tier: Tier = .normal, onCycle: Bool = false,
                energy: Double = 1.0, readiness: Int = 75) {
        self.tier = tier
        self.onCycle = onCycle
        self.energy = energy
        self.readiness = readiness
    }
}

/// Generating and reading a day. `now` and the RNG are injected so tests can fix both.
public enum DayService {
    /// The newest day that has a `DailyContext` — i.e. the last day the app actually generated.
    public static func lastProcessedDayKey(_ context: ModelContext) throws -> String? {
        try context.fetch(FetchDescriptor<DailyContext>()).map(\.dayKey).max()
    }

    public static func dailyContext(for dayKey: String, in context: ModelContext) throws -> DailyContext? {
        try context.fetch(FetchDescriptor<DailyContext>(
            predicate: #Predicate { $0.dayKey == dayKey })).first
    }

    public static func quests(on dayKey: String, in context: ModelContext) throws -> [DailyQuest] {
        try context.fetch(FetchDescriptor<DailyQuest>(predicate: #Predicate { $0.dayKey == dayKey }))
    }

    public static func occurrences(dueOn dayKey: String, in context: ModelContext) throws -> [RoutineOccurrence] {
        try context.fetch(FetchDescriptor<RoutineOccurrence>(predicate: #Predicate { $0.dueDayKey == dayKey }))
    }

    /// Every day that is over but not yet settled, oldest first: `[lastProcessed … yesterday]`.
    ///
    /// **Today is deliberately excluded.** A day is judged only once it has ended, so a routine due
    /// today is not counted as missed at 8am — it is settled tomorrow, when the app next opens.
    /// **The last processed day is deliberately included.** It was generated the day you opened the
    /// app, but nothing settled it before the day ran out.
    ///
    /// Stage 2 hangs the real work off `settle` (escalating overdue penalties, the day-4 auto-skip,
    /// Sunday's flexible settlement). The loop lives here because it has to run *before* today is
    /// generated, and it stays idempotent because generating today moves `lastProcessedDayKey`
    /// forward: a second call the same day finds `yesterday < last` and settles nothing.
    @discardableResult
    public static func catchUp(_ context: ModelContext,
                               openedOn today: String,
                               in timeZone: TimeZone = .current,
                               settle: (String, ModelContext) throws -> Void = { _, _ in }) throws -> [String] {
        guard let last = try lastProcessedDayKey(context),                 // nil = first ever launch
              let yesterday = DayKey.adding(-1, to: today, in: timeZone) else { return [] }
        let days = DayKey.range(from: last, through: yesterday, in: timeZone)
        for day in days { try settle(day, context) }
        return days
    }

    /// Generates today's context, today's routine occurrences and random slots, once.
    ///
    /// The routines come first because their count sizes the random slots (`PLAN.md` §3). Only
    /// routines **due today** count toward that load; an overdue one carried from an earlier day
    /// is already on the page but doesn't shrink today's random draw.
    ///
    /// Idempotency is keyed on `DailyContext`, not on `DailyQuest`: a day where every draw came
    /// back nil (small library, everything on cooldown) still counts as generated, otherwise the
    /// next foreground would generate it all over again.
    @discardableResult
    public static func ensureToday(_ context: ModelContext,
                                   now: Date = Date(),
                                   in timeZone: TimeZone = .current,
                                   inputs: DayInputs = DayInputs(),
                                   rng: inout some RandomNumberGenerator,
                                   settle: ((String, ModelContext) throws -> Void)? = nil) throws -> DailyContext {
        let today = now.dayKey(in: timeZone)          // taken once; everything below uses the key
        // Nil = the real settlement (`Overdue.settle`); tests may pass their own.
        try catchUp(context, openedOn: today, in: timeZone,
                    settle: settle ?? { try Overdue.settle($0, in: $1, timeZone: timeZone, now: now) })

        if let existing = try dailyContext(for: today, in: context) { return existing }

        let weekKey = DayKey.weekKey(of: today, in: timeZone) ?? now.weekKey(in: timeZone)
        let due = Schedule.dueRoutines(try context.fetch(FetchDescriptor<RoutineTask>()),
                                       occurrences: try context.fetch(FetchDescriptor<RoutineOccurrence>()),
                                       on: today, in: timeZone)
        for routine in due {
            context.insert(RoutineOccurrence(routine: routine, dueDayKey: today, weekKey: weekKey,
                                             tier: inputs.tier))
        }

        let day = DailyContext()
        day.dayKey = today
        day.tier = inputs.tier
        day.onCycle = inputs.onCycle
        day.energy = inputs.energy
        day.readiness = inputs.readiness
        day.routineLoad = due.count
        day.randomSlots = Composition.slots(routineLoad: due.count)
        context.insert(day)

        let templates = try Sampling.activeTemplates(context)
        let allowed = Composition.allowedIntensities(tier: inputs.tier, onCycle: inputs.onCycle)
        var drawn: Set<UUID> = []

        for slot in Composition.plan(tier: inputs.tier, slots: day.randomSlots, rng: &rng) {
            if slot.isTrivialGroup {
                let pool = Sampling.eligible(templates, difficulty: .trivial, dayKey: today,
                                             allowedIntensities: allowed, excluding: drawn, in: timeZone)
                let group = Sampling.pickDistinct(3, from: pool, rng: &rng)
                if group.count == 3 {
                    let variants = group.map { Sampling.variant(of: $0, rng: &rng) ?? "" }
                    let quest = DailyQuest(group: group, variants: variants,
                                           dayKey: today, weekKey: weekKey)
                    context.insert(quest)
                    for t in group {
                        t.lastServedDayKey = today
                        drawn.insert(t.id)
                    }
                    continue
                }
                // Fewer than three T items available: the slot falls back to a normal E draw.
            }
            let pool = Sampling.eligible(templates, difficulty: slot.difficulty, dayKey: today,
                                         allowedIntensities: allowed, excluding: drawn, in: timeZone)
            guard let template = Sampling.pick(from: pool, rng: &rng) else { continue }
            context.insert(DailyQuest(template: template, slot: slot.difficulty,
                                      dayKey: today, weekKey: weekKey,
                                      variant: Sampling.variant(of: template, rng: &rng)))
            template.lastServedDayKey = today
            drawn.insert(template.id)
        }

        try context.save()
        return day
    }

    /// Whether the hidden slot may be drawn: every `countsForClear` routine done, every random
    /// slot done (`PLAN.md` §3). `replaced` slots don't count — an ad-hoc routine took them.
    public static func hiddenUnlocked(on dayKey: String, in context: ModelContext) throws -> Bool {
        let quests = try quests(on: dayKey, in: context)
        // No random slot was filled at all (tiny library, or everything on cooldown): there is
        // nothing to clear, so there is no hidden reward either — the day is simply yours.
        guard quests.contains(where: { !$0.isHiddenSlot }) else { return false }
        let randomsDone = quests
            .filter { !$0.isHiddenSlot && !$0.replaced && $0.slot != .epic }
            .allSatisfy { $0.completedAt != nil }
        let occurrences = try occurrences(dueOn: dayKey, in: context)
        // `countsForClear = false` routines (the check-in kind) are recorded but never gate the
        // day — PLAN.md §3. The flag is read off the occurrence's own snapshot, not the routine.
        let routinesDone = occurrences
            .filter(\.countsForClear)
            .allSatisfy { $0.completedDayKey != nil || $0.skipped }
        return randomsDone && routinesDone
    }

    /// Draws the hidden quest, once per day, and only after the day is fully cleared.
    @discardableResult
    public static func drawHidden(_ context: ModelContext,
                                  on dayKey: String,
                                  in timeZone: TimeZone = .current,
                                  inputs: DayInputs = DayInputs(),
                                  rng: inout some RandomNumberGenerator) throws -> DailyQuest? {
        let existing = try quests(on: dayKey, in: context)
        guard !existing.contains(where: \.isHiddenSlot),
              try hiddenUnlocked(on: dayKey, in: context) else { return nil }

        let allowed = Composition.allowedIntensities(tier: inputs.tier, onCycle: inputs.onCycle)
        let drawn = Set(existing.compactMap(\.templateID) + existing.flatMap(\.trivialTemplateIDs))
        let pool = Sampling.eligibleHidden(try Sampling.activeTemplates(context), dayKey: dayKey,
                                           allowedIntensities: allowed, excluding: drawn, in: timeZone)
        guard let template = Sampling.pick(from: pool, rng: &rng) else { return nil }

        let weekKey = DayKey.weekKey(of: dayKey, in: timeZone) ?? ""
        // Hidden pays the template's own difficulty plus the flat bonus, so the slot is that
        // difficulty rather than a tier of its own.
        let quest = DailyQuest(template: template, slot: template.difficulty,
                               dayKey: dayKey, weekKey: weekKey,
                               variant: Sampling.variant(of: template, rng: &rng))
        quest.isHiddenSlot = true
        context.insert(quest)
        template.lastServedDayKey = dayKey
        try context.save()
        return quest
    }
}

extension DailyQuest {
    /// One template in one slot. The text is snapshotted: history never points back at the
    /// template, so editing or deleting it later can't rewrite what was done.
    /// `variant` is the value drawn from a parameterized template (`PLAN.md` "Parameterized
    /// templates"). It is kept beside the text rather than spliced into it: the CSV wording stays
    /// the row's identity, and the history records both what the template said and what was
    /// actually asked of you that day.
    public convenience init(template: QuestTemplate, slot: Difficulty, dayKey: String, weekKey: String,
                            variant: String? = nil) {
        self.init()
        self.dayKey = dayKey
        self.weekKey = weekKey
        self.slot = slot
        templateID = template.id
        textSnapshot = template.text
        variantSnapshot = variant
        launchURLSnapshot = template.launchURLString
    }

    /// A T group in an E slot: three texts, one score of 12.
    public convenience init(group: [QuestTemplate], variants: [String] = [],
                            dayKey: String, weekKey: String) {
        self.init()
        self.dayKey = dayKey
        self.weekKey = weekKey
        slot = .easy                                  // the slot it occupies, not its own tier
        trivialGroup = group.map(\.text)
        trivialTemplateIDs = group.map(\.id)
        trivialVariants = variants.count == group.count ? variants
                                                        : Array(repeating: "", count: group.count)
        trivialDone = Array(repeating: false, count: group.count)
        textSnapshot = group.map(\.text).joined(separator: " · ")
    }
}

extension RoutineOccurrence {
    /// One routine due on one day. Text, points and the full-clear flag are snapshotted, so
    /// editing the routine later can't rewrite what was asked of you that day. On a low `tier`
    /// day a routine with a light version starts out as that version (`Degrade`).
    public convenience init(routine: RoutineTask, dueDayKey: String, weekKey: String,
                            tier: Tier = .normal) {
        self.init()
        routineID = routine.id
        self.dueDayKey = dueDayKey
        self.weekKey = weekKey
        textSnapshot = routine.text
        basePoints = routine.basePoints
        countsForClear = routine.countsForClear
        if let light = Degrade.text(for: routine, tier: tier) {
            degradedTextSnapshot = light
            usedDegraded = true
        }
    }
}
