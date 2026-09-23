import Foundation

/// One day of body data, as read from HealthKit. Nil = no sample that day.
///
/// Which samples make up a day (the sleep window, which HRV samples) is the app's reading of
/// HealthKit and lives in the app; Core only sees the three numbers.
public struct HealthReading: Equatable, Sendable {
    public var dayKey: String
    public var hrv: Double?            // SDNN, ms
    public var sleepHours: Double?
    public var restingHR: Double?      // bpm

    public init(dayKey: String, hrv: Double? = nil, sleepHours: Double? = nil, restingHR: Double? = nil) {
        self.dayKey = dayKey
        self.hrv = hrv
        self.sleepHours = sleepHours
        self.restingHR = restingHR
    }
}

/// Energy score, readiness and tier (`PLAN.md` §5).
///
/// ```
/// E = 0.45 × (hrv / hrvMedian) + 0.35 × (sleep / sleepMedian) + 0.20 × (rhrMedian / rhr)
/// ```
/// each ratio clamped to [0.6, 1.4]. A metric with no value today, or with fewer than
/// `minimumDays` of history, is left out and the remaining weights are renormalised — a night
/// without the watch shouldn't read as a terrible night. With nothing usable the day is `normal`.
public enum Energy {
    public static let weights = (hrv: 0.45, sleep: 0.35, restingHR: 0.20)
    public static let ratioBounds: ClosedRange<Double> = 0.6...1.4
    /// The baseline is the median of the `window` days before today (today excluded).
    public static let window = 28
    /// Fewer values than this in the window and that metric has no baseline yet.
    public static let minimumDays = 7

    public struct Baseline: Equatable, Sendable {
        public var hrv: Double?
        public var sleepHours: Double?
        public var restingHR: Double?

        public init(hrv: Double?, sleepHours: Double?, restingHR: Double?) {
            self.hrv = hrv
            self.sleepHours = sleepHours
            self.restingHR = restingHR
        }
    }

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let mid = s.count / 2
        return s.count.isMultiple(of: 2) ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    /// Per-metric median over `[dayKey − 28 … dayKey − 1]`. Non-positive values are bad samples
    /// and are ignored, like missing ones.
    public static func baseline(_ history: [HealthReading], before dayKey: String,
                                in timeZone: TimeZone = .current) -> Baseline {
        guard let first = DayKey.adding(-window, to: dayKey, in: timeZone) else {
            return Baseline(hrv: nil, sleepHours: nil, restingHR: nil)
        }
        let inWindow = history.filter { $0.dayKey >= first && $0.dayKey < dayKey }
        func metric(_ value: (HealthReading) -> Double?) -> Double? {
            let values = inWindow.compactMap(value).filter { $0 > 0 }
            return values.count >= minimumDays ? median(values) : nil
        }
        return Baseline(hrv: metric(\.hrv), sleepHours: metric(\.sleepHours), restingHR: metric(\.restingHR))
    }

    /// E for one day, or nil when no metric can be judged.
    public static func score(_ today: HealthReading, baseline: Baseline) -> Double? {
        func ratio(_ numerator: Double?, _ denominator: Double?) -> Double? {
            guard let n = numerator, let d = denominator, n > 0, d > 0 else { return nil }
            return min(max(n / d, ratioBounds.lowerBound), ratioBounds.upperBound)
        }
        let terms: [(weight: Double, ratio: Double?)] = [
            (weights.hrv, ratio(today.hrv, baseline.hrv)),
            (weights.sleep, ratio(today.sleepHours, baseline.sleepHours)),
            // Resting HR is inverse: a higher-than-usual pulse is the bad sign.
            (weights.restingHR, ratio(baseline.restingHR, today.restingHR)),
        ]
        let used = terms.compactMap { t in t.ratio.map { (t.weight, $0) } }
        let totalWeight = used.reduce(0) { $0 + $1.0 }
        guard totalWeight > 0 else { return nil }
        return used.reduce(0) { $0 + $1.0 * $1.1 } / totalWeight
    }

    /// `clamp(round(E × 75), 35, 100)`, rounding half up like every other score.
    public static func readiness(_ energy: Double) -> Int {
        let r = Int((energy * 75).rounded(.toNearestOrAwayFromZero))
        return min(max(r, 35), 100)
    }

    /// E < 0.85 very low, 0.85 ..< 0.92 low, 0.92 ... 1.06 normal, > 1.06 high.
    public static func tier(_ energy: Double) -> Tier {
        switch energy {
        case ..<0.85: .veryLow
        case ..<0.92: .low
        case ...1.06: .normal
        default: .high
        }
    }

    /// What a cycle day does to the tier (`PLAN.md` §5, "Menstrual cycle").
    ///
    /// The **first three days** are held down to `low`: that one line is the whole rule, because
    /// a low day already means fewer and easier random slots, the 1.3× effort multiplier, and
    /// routines swapped for their downgrade version — no strength session on day 1. A measured
    /// `veryLow` stays `veryLow`; this never pushes a tier *up*. Later cycle days are only capped
    /// at normal, as before: being on a period is not the same as being weak.
    public static func cap(_ tier: Tier, cycleDay: Int?) -> Tier {
        guard let cycleDay else { return tier }
        if cycleDay <= Cycle.earlyDays { return tier.isLow ? tier : .low }
        return tier == .high ? .normal : tier
    }

    /// Everything `ensureToday` needs from the body, in one call.
    public static func inputs(today: HealthReading, history: [HealthReading], cycleDay: Int?,
                              in timeZone: TimeZone = .current) -> DayInputs {
        var inputs = DayInputs(cycleDay: cycleDay)
        inputs.hrv = today.hrv
        inputs.sleepHours = today.sleepHours
        inputs.restingHR = today.restingHR
        guard let e = score(today, baseline: baseline(history, before: today.dayKey, in: timeZone)) else {
            // No usable reading: the day is `normal` — but a cycle day still applies.
            inputs.tier = cap(.normal, cycleDay: cycleDay)
            return inputs
        }
        inputs.energy = e
        inputs.readiness = readiness(e)
        inputs.tier = cap(tier(e), cycleDay: cycleDay)
        return inputs
    }
}
