import Foundation

/// A calendar month, `"2026-09"`. Like `dayKey`, a string-shaped business key rather than a `Date`.
public struct MonthKey: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int

    public init?(year: Int, month: Int) {
        guard (1...12).contains(month), (1...9999).contains(year) else { return nil }
        self.year = year
        self.month = month
    }

    /// The month a `dayKey` falls in.
    public init?(dayKey: String) {
        let parts = dayKey.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), Int(parts[2]) != nil else { return nil }
        self.init(year: y, month: m)
    }

    public var description: String { String(format: "%04d-%02d", year, month) }

    public var firstDayKey: String { String(format: "%04d-%02d-01", year, month) }

    public func adding(_ months: Int) -> MonthKey {
        let index = year * 12 + (month - 1) + months
        return MonthKey(year: index / 12, month: index % 12 + 1) ?? self
    }

    public static func < (a: MonthKey, b: MonthKey) -> Bool { (a.year, a.month) < (b.year, b.month) }
}

/// The month page's grid: whole Monday-start weeks covering the month, padded with the
/// neighbouring months' days. Monday-start so each row is exactly one ISO week and carries that
/// week's `weekKey` — which is what the epic highlight is judged by (`PLAN.md` §9).
public struct MonthGrid: Equatable, Sendable {
    public struct Day: Equatable, Hashable, Sendable {
        public let dayKey: String
        public let dayOfMonth: Int
        /// False for the padding days from the months either side.
        public let inMonth: Bool
    }

    public struct Week: Equatable, Sendable {
        public let weekKey: String
        public let days: [Day]           // always 7, Monday first
    }

    public let month: MonthKey
    public let weeks: [Week]

    public init(_ month: MonthKey, in timeZone: TimeZone = .current) {
        self.month = month
        let first = month.firstDayKey
        // Gregorian weekday: Sunday = 1 … Saturday = 7. Days back to that week's Monday:
        let weekday = DayKey.weekday(of: first, in: timeZone)?.rawValue ?? 2
        let lead = (weekday + 5) % 7
        var cursor = DayKey.adding(-lead, to: first, in: timeZone) ?? first
        let next = month.adding(1)

        var weeks: [Week] = []
        while weeks.count < 6 {
            var days: [Day] = []
            for _ in 0..<7 {
                let parts = cursor.split(separator: "-")
                days.append(Day(dayKey: cursor,
                                dayOfMonth: Int(parts[2]) ?? 0,
                                inMonth: MonthKey(dayKey: cursor) == month))
                cursor = DayKey.adding(1, to: cursor, in: timeZone) ?? cursor
            }
            weeks.append(Week(weekKey: DayKey.weekKey(of: days[0].dayKey, in: timeZone) ?? "",
                              days: days))
            if MonthKey(dayKey: cursor).map({ $0 >= next }) ?? true { break }
        }
        self.weeks = weeks
    }
}
