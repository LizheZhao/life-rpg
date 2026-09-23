import Foundation
import HealthKit
import LifeRPGCore

/// Reads the body data Stage 3 feeds into the day: sleep, HRV and resting HR for the energy score,
/// menstrual flow for the cycle cap, mindful sessions for auto-verification.
///
/// Queries only. Which samples belong to which day is `HealthBuckets`, the score is `Energy` —
/// both in Core. HealthKit never says whether *read* access was granted: a denied type simply
/// returns nothing, which the score treats as missing data, i.e. a `normal` day.
final class HealthService {
    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [HKCategoryType(.sleepAnalysis),
         HKQuantityType(.heartRateVariabilitySDNN),
         HKQuantityType(.restingHeartRate),
         HKCategoryType(.mindfulSession),
         HKCategoryType(.menstrualFlow)]
    }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Everything that goes into a day's tier: the reading, the baseline it is judged against,
    /// and the result. `inputs` is what generation uses; the debug page shows the whole thing.
    /// How far back flow entries are read, in days — long enough to find the start of a round.
    private let cycleWindow = 14

    struct Body {
        var today: HealthReading
        var baseline: Energy.Baseline
        var inputs: DayInputs
    }

    /// Today's `DayInputs`: today's reading against the 28 days before it, capped on a cycle day.
    /// The whole history is re-read each time rather than stored — it is what the first-launch
    /// backfill in `PLAN.md` §5 amounts to, and it only runs once a day, when the day is generated.
    func inputs(for dayKey: String, now: Date) async throws -> DayInputs {
        try await body(for: dayKey, now: now).inputs
    }

    /// Reads and scores the body for `dayKey`. Writes nothing.
    func body(for dayKey: String, now: Date) async throws -> Body {
        guard let firstDay = DayKey.adding(-Energy.window, to: dayKey),
              let from = HealthBuckets.sleepWindow(for: firstDay)?.start else {
            return Body(today: HealthReading(dayKey: dayKey),
                        baseline: .init(hrv: nil, sleepHours: nil, restingHR: nil), inputs: DayInputs())
        }
        let days = DayKey.range(from: firstDay, through: dayKey)

        async let asleep = asleepIntervals(from: from, to: now)
        async let hrv = values(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: from, to: now)
        async let rhr = values(.restingHeartRate, unit: .count().unitDivided(by: .minute()), from: from, to: now)
        async let cycle = cycleDay(dayKey)

        let readings = HealthBuckets.readings(for: days, asleep: try await asleep,
                                              hrv: try await hrv, restingHR: try await rhr)
        let today = readings.last ?? HealthReading(dayKey: dayKey)
        let history = Array(readings.dropLast())
        return Body(today: today,
                    baseline: Energy.baseline(history, before: dayKey),
                    inputs: Energy.inputs(today: today, history: history, cycleDay: try await cycle))
    }

    func mindfulSessions(from: Date, to: Date) async throws -> [MindfulSession] {
        try await categorySamples(.mindfulSession, from: from, to: to)
            .map { MindfulSession(start: $0.startDate, end: $0.endDate) }
    }

    // MARK: queries

    private func asleepIntervals(from: Date, to: Date) async throws -> [DateInterval] {
        let asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
        return try await categorySamples(.sleepAnalysis, from: from, to: to)
            .filter { asleep.contains($0.value) }       // not `inBed` or `awake`
            .map { DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate)) }
    }

    /// Which day of the period `dayKey` is (`Cycle.day`), or nil.
    ///
    /// Two weeks of flow entries are read rather than just today's: the rule counts calendar days
    /// from the day the round started, so a day logged earlier is what tells day 1 from day 3.
    /// A logged "none" is a record of *no* flow, so it doesn't count.
    private func cycleDay(_ dayKey: String) async throws -> Int? {
        guard let noon = DayKey.date(dayKey),
              let first = DayKey.adding(-cycleWindow, to: dayKey),
              let firstNoon = DayKey.date(first) else { return nil }
        let start = LifeCalendar.gregorian().startOfDay(for: firstNoon)
        guard let end = LifeCalendar.gregorian().date(byAdding: .day, value: 1,
                                                      to: LifeCalendar.gregorian().startOfDay(for: noon))
        else { return nil }
        let none: Int
        if #available(iOS 18.0, *) {
            none = HKCategoryValueVaginalBleeding.none.rawValue
        } else {
            none = HKCategoryValueMenstrualFlow.none.rawValue
        }
        let flowDays = try await categorySamples(.menstrualFlow, from: start, to: end)
            .filter { $0.value != none }
            .map { $0.startDate.dayKey }
        return Cycle.day(on: dayKey, flowDays: Set(flowDays))
    }

    private func categorySamples(_ id: HKCategoryTypeIdentifier, from: Date, to: Date) async throws -> [HKCategorySample] {
        let query = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(id),
                                         predicate: HKQuery.predicateForSamples(withStart: from, end: to))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        return try await query.result(for: store)
    }

    private func values(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date) async throws -> [TimedValue] {
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id),
                                         predicate: HKQuery.predicateForSamples(withStart: from, end: to))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        return try await query.result(for: store)
            .map { TimedValue(date: $0.startDate, value: $0.quantity.doubleValue(for: unit)) }
    }
}
