import Foundation
import SwiftData

/// Which calendar events count as workouts. **Both halves are required**: the event must be in
/// the chosen calendar (the one the Shortcut writes to) *and* its title must contain one of the
/// keywords. An unset half matches nothing, so an unconfigured app never mistakes a long meeting
/// for a workout.
public struct WorkoutFilter: Equatable, Sendable {
    public var calendarID: String
    public var keywords: [String]

    public init(calendarID: String, keywords: [String]) {
        self.calendarID = calendarID
        self.keywords = keywords
    }

    /// `" Workout, 运动 ,,"` → `["Workout", "运动"]` — the form the setting is stored in.
    public static func keywords(from setting: String) -> [String] {
        setting.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public func matches(_ event: CalendarEvent) -> Bool {
        let words = keywords.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !calendarID.isEmpty, !words.isEmpty, !event.isAllDay,
              event.calendarID == calendarID else { return false }
        return words.contains { event.title.range(of: $0, options: [.caseInsensitive]) != nil }
    }
}

/// A calendar event as the app reads it from EventKit.
public struct CalendarEvent: Equatable, Sendable {
    public var calendarID: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool

    public init(calendarID: String, title: String, start: Date, end: Date, isAllDay: Bool = false) {
        self.calendarID = calendarID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
    }
}

/// A HealthKit `mindfulSession` sample.
public struct MindfulSession: Equatable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

/// What one day offers as proof: total mindful minutes (sessions accumulate, `PLAN.md` §5) and
/// the length of each qualifying workout.
public struct DayEvidence: Equatable, Sendable {
    public var mindfulMinutes: Double
    public var workoutMinutes: [Double]

    public init(mindfulMinutes: Double = 0, workoutMinutes: [Double] = []) {
        self.mindfulMinutes = mindfulMinutes
        self.workoutMinutes = workoutMinutes
    }
}

/// Auto-verification (`PLAN.md` §5): completes open quests and routines whose `auto_verify` rule
/// the day's evidence satisfies, through the same `Completion` paths a tap uses, marked
/// `sourceType = .healthKit`.
///
/// **Evidence is spent, not shared.** One workout verifies one thing, and mindful minutes are
/// drawn down as they're used — otherwise a single 45-minute session would pay for the routine
/// *and* the "go for a walk" quest. Items already completed that day (by hand or automatically)
/// spend their evidence first, so running again on the next foreground can't hand the same event
/// to a quest drawn since. Within that, routines go before quests (a missed routine is penalised,
/// a missed quest isn't), oldest due first, and each item takes the shortest event that is long
/// enough, leaving the long one for the threshold that needs it.
///
/// Not covered: `calendar_workout_weekly` (the epic's, Stage 5), T groups, epic slots, and ad-hoc
/// occurrences — they have no routine to read a rule from.
public enum AutoVerify {
    /// Groups raw samples into per-day evidence, keyed by the day each one **starts** on.
    public static func evidence(events: [CalendarEvent], mindful: [MindfulSession],
                                filter: WorkoutFilter,
                                in timeZone: TimeZone = .current) -> [String: DayEvidence] {
        var out: [String: DayEvidence] = [:]
        for e in events where filter.matches(e) {
            out[e.start.dayKey(in: timeZone), default: DayEvidence()]
                .workoutMinutes.append(e.end.timeIntervalSince(e.start) / 60)
        }
        for s in mindful {
            out[s.start.dayKey(in: timeZone), default: DayEvidence()]
                .mindfulMinutes += max(0, s.end.timeIntervalSince(s.start) / 60)
        }
        return out
    }

    /// Completes what `evidence` proves on `dayKey`. Returns how many items it completed.
    /// Idempotent: a second run with the same evidence completes nothing.
    @discardableResult
    public static func run(on dayKey: String, evidence: DayEvidence,
                           in context: ModelContext, now: Date = Date(),
                           timeZone: TimeZone = .current,
                           rng: inout some RandomNumberGenerator) throws -> Int {
        let tier = try DayService.dailyContext(for: dayKey, in: context)?.tier ?? .normal
        let routines = try context.fetch(FetchDescriptor<RoutineTask>())
        let rules = Dictionary(routines.compactMap { r in r.autoVerify.map { (r.id, $0) } },
                               uniquingKeysWith: { a, _ in a })
        let flexible = Set(routines.filter(\.flexibleWithinWeek).map(\.id))
        let templates = try context.fetch(FetchDescriptor<QuestTemplate>())
        let templateRules = Dictionary(templates.compactMap { t in t.autoVerify.map { (t.id, $0) } },
                                       uniquingKeysWith: { a, _ in a })

        let occurrences = try context.fetch(FetchDescriptor<RoutineOccurrence>())
            .sorted { $0.dueDayKey < $1.dueDayKey }
        let quests = try DayService.quests(on: dayKey, in: context)
            .filter { !$0.isTrivialGroup && !$0.replaced && $0.slot != .epic }
            .sorted { (!$0.isHiddenSlot && $1.isHiddenSlot) }

        // The version currently chosen is the one that has to be proved: a 30-minute walk
        // verifies the walk, not the 40-minute strength session it replaced.
        func rule(_ o: RoutineOccurrence) -> AutoVerifyRule? {
            let id = o.usedDegraded ? (o.degradedRoutineID ?? o.routineID) : o.routineID
            return id.flatMap { rules[$0] }
        }
        func rule(_ q: DailyQuest) -> AutoVerifyRule? { q.templateID.flatMap { templateRules[$0] } }

        var pool = Pool(evidence)

        // What is already done today has spent its evidence.
        for o in occurrences where o.completedDayKey == dayKey { rule(o).map { _ = pool.spend($0) } }
        for q in quests where q.completedAt != nil { rule(q).map { _ = pool.spend($0) } }

        var completed = 0
        for o in occurrences where Schedule.isOpen(o) && o.dueDayKey <= dayKey {
            guard let r = rule(o),
                  Completion.routinePayout(o, flexible: Schedule.isFlexible(o, flexible), on: dayKey,
                                           tier: tier, in: timeZone) != nil,
                  pool.spend(r) else { continue }
            try Completion.completeRoutine(o, on: dayKey, tier: tier, in: context, now: now,
                                           timeZone: timeZone, source: .healthKit)
            completed += 1
        }
        for q in quests where q.completedAt == nil {
            guard let r = rule(q), pool.spend(r) else { continue }
            try Completion.complete(q, tier: tier, in: context, now: now, source: .healthKit, rng: &rng)
            completed += 1
        }
        return completed
    }

    /// The day's evidence, drawn down as items claim it.
    struct Pool {
        var mindful: Double
        var workouts: [Double]           // ascending, so the first long-enough one is the shortest

        init(_ e: DayEvidence) {
            mindful = e.mindfulMinutes
            workouts = e.workoutMinutes.sorted()
        }

        /// Claims what `rule` needs; false (and nothing claimed) when the day can't cover it.
        mutating func spend(_ rule: AutoVerifyRule) -> Bool {
            switch rule {
            case .mindful(let minutes):
                guard mindful >= Double(minutes) else { return false }
                mindful -= Double(minutes)
                return true
            case .calendarWorkout(let minutes):
                guard let i = workouts.firstIndex(where: { $0 >= Double(minutes) }) else { return false }
                workouts.remove(at: i)
                return true
            case .calendarWorkoutWeekly:
                return false
            }
        }
    }
}
