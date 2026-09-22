import Foundation

/// One HealthKit quantity sample, reduced to its time and value.
public struct TimedValue: Equatable, Sendable {
    public var date: Date
    public var value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// Turns raw HealthKit samples into one `HealthReading` per day. The app queries; this decides
/// which samples belong to which day, so the rule is tested and lives in one place.
///
/// - **Sleep** for day D is the night *before* it: asleep samples ending in `[D−1 18:00, D 12:00)`.
///   Overlapping samples are merged first — the Watch and Oura both write sleep, and summing
///   them would count the same night twice.
/// - **HRV** is the mean of the samples taken in that same window, i.e. overnight.
/// - **Resting HR** is the latest sample in `[D−1 00:00, D 12:00)` — Apple writes one per day, so
///   in the morning this is usually yesterday's.
public enum HealthBuckets {
    public static let windowStartHour = 18       // on the previous day
    public static let windowEndHour = 12

    public static func sleepWindow(for dayKey: String, in timeZone: TimeZone = .current) -> DateInterval? {
        let cal = LifeCalendar.gregorian(timeZone)
        guard let previous = DayKey.adding(-1, to: dayKey, in: timeZone).flatMap({ DayKey.date($0, in: timeZone) }),
              let day = DayKey.date(dayKey, in: timeZone),
              let start = cal.date(bySettingHour: windowStartHour, minute: 0, second: 0, of: previous),
              let end = cal.date(bySettingHour: windowEndHour, minute: 0, second: 0, of: day),
              start < end else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Hours covered by the union of `intervals`.
    public static func unionHours(_ intervals: [DateInterval]) -> Double {
        var total: TimeInterval = 0
        var current: DateInterval?
        for i in intervals.sorted(by: { $0.start < $1.start }) {
            if let c = current, i.start <= c.end {
                current = DateInterval(start: c.start, end: max(c.end, i.end))
            } else {
                if let c = current { total += c.duration }
                current = i
            }
        }
        if let c = current { total += c.duration }
        return total / 3600
    }

    public static func reading(for dayKey: String, asleep: [DateInterval], hrv: [TimedValue],
                               restingHR: [TimedValue], in timeZone: TimeZone = .current) -> HealthReading {
        var r = HealthReading(dayKey: dayKey)
        guard let window = sleepWindow(for: dayKey, in: timeZone) else { return r }
        // Midnight starting yesterday: the window opens at 18:00 on that same day.
        let rhrStart = LifeCalendar.gregorian(timeZone).startOfDay(for: window.start)
        let inWindow = { (d: Date) in d >= window.start && d < window.end }

        let hours = unionHours(asleep.filter { inWindow($0.end) })
        r.sleepHours = hours > 0 ? hours : nil

        let overnight = hrv.filter { inWindow($0.date) && $0.value > 0 }.map(\.value)
        r.hrv = overnight.isEmpty ? nil : overnight.reduce(0, +) / Double(overnight.count)

        r.restingHR = restingHR
            .filter { $0.date >= rhrStart && $0.date < window.end && $0.value > 0 }
            .max { $0.date < $1.date }?.value
        return r
    }

    public static func readings(for dayKeys: [String], asleep: [DateInterval], hrv: [TimedValue],
                                restingHR: [TimedValue], in timeZone: TimeZone = .current) -> [HealthReading] {
        dayKeys.map { reading(for: $0, asleep: asleep, hrv: hrv, restingHR: restingHR, in: timeZone) }
    }
}
