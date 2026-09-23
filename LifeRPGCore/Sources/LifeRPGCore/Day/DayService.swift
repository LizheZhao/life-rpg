import Foundation
import SwiftData

/// The per-day inputs `ensureToday` needs but cannot measure itself.
///
/// The app fills them from HealthKit through `Energy.inputs`; the defaults are what a day with no
/// body data gets (`normal`). The raw readings ride along so the day records what it was judged on. Routine load is **not** here: it is counted from the occurrences `ensureToday`
/// schedules, so the number that sizes the random slots and the routines on the page can't disagree.
public struct DayInputs: Equatable, Sendable {
    public var tier: Tier
    /// Which day of the period this is, 1-based (`Cycle.day`), or nil. Days 1–3 are already
    /// reflected in `tier` — `Energy.cap` holds it down to `low` — so nothing downstream reads
    /// this except the day's own record.
    public var cycleDay: Int?
    public var energy: Double
    public var readiness: Int
    public var hrv: Double?
    public var sleepHours: Double?
    public var restingHR: Double?

    /// True on any day inside a period, which is what the day's record and `PLAN.md` §5 call
    /// "on cycle".
    public var onCycle: Bool { cycleDay != nil }

    public init(tier: Tier = .normal, cycleDay: Int? = nil,
                energy: Double = 1.0, readiness: Int = 75) {
        self.tier = tier
        self.cycleDay = cycleDay
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
                                   evidence: [String: DayEvidence] = [:],
                                   rng: inout some RandomNumberGenerator,
                                   settle: ((String, ModelContext) throws -> Void)? = nil) throws -> DailyContext {
        let today = now.dayKey(in: timeZone)          // taken once; everything below uses the key
        // Nil = the real settlement (`Overdue.settle`); tests may pass their own.
        let judge = settle ?? { try Overdue.settle($0, in: $1, timeZone: timeZone, now: now) }
        // Each ended day is auto-verified from its own evidence *before* it is judged, so a workout
        // logged on a day the app never saw still counts on that day rather than being docked.
        try catchUp(context, openedOn: today, in: timeZone, settle: { day, ctx in
            if let e = evidence[day] {
                try AutoVerify.run(on: day, evidence: e, in: ctx, now: now, timeZone: timeZone, rng: &rng)
            }
            try judge(day, ctx)
        })

        if let existing = try dailyContext(for: today, in: context) {
            // Every foreground re-checks today: a workout that synced since the last one lands now.
            if let e = evidence[today] {
                try AutoVerify.run(on: today, evidence: e, in: context, now: now, timeZone: timeZone, rng: &rng)
            }
            return existing
        }

        let weekKey = DayKey.weekKey(of: today, in: timeZone) ?? now.weekKey(in: timeZone)
        let routines = try context.fetch(FetchDescriptor<RoutineTask>())
        let due = Schedule.dueRoutines(routines,
                                       occurrences: try context.fetch(FetchDescriptor<RoutineOccurrence>()),
                                       on: today, in: timeZone)
        for routine in due {
            let light = Degrade.pick(for: routine, tier: inputs.tier, in: routines, rng: &rng)
            context.insert(RoutineOccurrence(routine: routine, dueDayKey: today, weekKey: weekKey,
                                             downgrade: light))
        }

        let day = DailyContext()
        day.dayKey = today
        day.tier = inputs.tier
        day.onCycle = inputs.onCycle
        day.cycleDay = inputs.cycleDay
        day.energy = inputs.energy
        day.readiness = inputs.readiness
        day.hrv = inputs.hrv
        day.sleepHours = inputs.sleepHours
        day.restingHR = inputs.restingHR
        day.routineLoad = due.count
        day.randomSlots = Composition.slots(routineLoad: due.count)
        context.insert(day)

        var drawn: Set<UUID> = []
        try fill(context, plan: Composition.plan(tier: inputs.tier, slots: day.randomSlots),
                 on: today, weekKey: weekKey, excluding: &drawn, in: timeZone, rng: &rng)

        try context.save()
        if let e = evidence[today] {
            try AutoVerify.run(on: today, evidence: e, in: context, now: now, timeZone: timeZone, rng: &rng)
        }
        return day
    }

    /// Draws one template into each planned slot, skipping anything in `drawn` and adding what
    /// it draws to it. Shared by the first generation of a day and by `Replan`, so a re-plan
    /// fills a slot exactly the way the morning would have.
    static func fill(_ context: ModelContext,
                     plan: [Difficulty],
                     on dayKey: String,
                     weekKey: String,
                     excluding drawn: inout Set<UUID>,
                     in timeZone: TimeZone = .current,
                     rng: inout some RandomNumberGenerator) throws {
        let templates = try Sampling.activeTemplates(context)
        for slot in plan {
            if slot == .trivial {
                let pool = Sampling.eligible(templates, difficulty: .trivial, dayKey: dayKey,
                                             excluding: drawn, in: timeZone)
                let group = Sampling.pickDistinct(3, from: pool, rng: &rng)
                if group.count == 3 {
                    let variants = group.map { Sampling.variant(of: $0, rng: &rng) ?? "" }
                    let quest = DailyQuest(group: group, variants: variants,
                                           dayKey: dayKey, weekKey: weekKey)
                    context.insert(quest)
                    for t in group {
                        t.lastServedDayKey = dayKey
                        drawn.insert(t.id)
                    }
                    continue
                }
                // Fewer than three T items available: the slot falls back to a normal E draw.
            }
            let difficulty = slot == .trivial ? .easy : slot
            let pool = Sampling.eligible(templates, difficulty: difficulty, dayKey: dayKey,
                                         excluding: drawn, in: timeZone)
            guard let template = Sampling.pick(from: pool, rng: &rng) else { continue }
            context.insert(DailyQuest(template: template, slot: difficulty,
                                      dayKey: dayKey, weekKey: weekKey,
                                      variant: Sampling.variant(of: template, rng: &rng)))
            template.lastServedDayKey = dayKey
            drawn.insert(template.id)
        }
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

        let drawn = Set(existing.compactMap(\.templateID) + existing.flatMap(\.trivialTemplateIDs))
        let pool = Sampling.eligibleHidden(try Sampling.activeTemplates(context), dayKey: dayKey,
                                           excluding: drawn, in: timeZone)
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
        slot = .trivial                               // T is its own rung, below E
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
    /// editing the routine later can't rewrite what was asked of you that day. `downgrade` is the
    /// lighter version drawn for the day (`Degrade.pick`), if any: the occurrence starts out as
    /// that version, and keeps the original beside it so it can be switched back.
    public convenience init(routine: RoutineTask, dueDayKey: String, weekKey: String,
                            downgrade: RoutineTask? = nil) {
        self.init()
        routineID = routine.id
        self.dueDayKey = dueDayKey
        self.weekKey = weekKey
        textSnapshot = routine.text
        basePoints = routine.basePoints
        countsForClear = routine.countsForClear
        if let downgrade {
            degradedTextSnapshot = downgrade.text
            degradedRoutineID = downgrade.id
            degradedBasePoints = downgrade.basePoints
            usedDegraded = true
        }
    }
}
