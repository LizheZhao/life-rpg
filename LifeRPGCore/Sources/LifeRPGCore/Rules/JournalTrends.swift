import Foundation

/// The rules behind the Trends page. Everything here is a pure function of rows the page already
/// holds (`JournalDay`, `DailyQuest` and the like), so a number on the page cannot drift from the
/// journal or the calendar it summarises. Nothing is stored.
public enum JournalTrends {
    /// What the Weeks / Months / Year switch selects.
    public enum Period: String, CaseIterable, Sendable {
        case week, month, year
    }

    /// First and last `dayKey` of a period, both inclusive.
    public struct DayRange: Equatable, Sendable {
        public let first: String
        public let last: String

        public init(first: String, last: String) {
            self.first = first
            self.last = last
        }

        public func contains(_ dayKey: String) -> Bool { first <= dayKey && dayKey <= last }

        /// Every day of the range in order, so a day with nothing in it still has its slot.
        public func days(in timeZone: TimeZone = .current) -> [String] {
            DayKey.range(from: first, through: last, in: timeZone)
        }
    }

    /// The period that holds `dayKey`. Weeks run Monday to Sunday as the month grid's rows do,
    /// months and years are calendar ones. Nil only for a malformed key.
    public static func range(of period: Period, containing dayKey: String,
                             in timeZone: TimeZone = .current) -> DayRange? {
        guard DayKey.isValid(dayKey, in: timeZone) else { return nil }
        switch period {
        case .week:
            // Gregorian weekday: Sunday = 1, so Monday is 0 days back and Sunday 6.
            guard let weekday = DayKey.weekday(of: dayKey, in: timeZone),
                  let first = DayKey.adding(-((weekday.rawValue + 5) % 7), to: dayKey, in: timeZone),
                  let last = DayKey.adding(6, to: first, in: timeZone) else { return nil }
            return DayRange(first: first, last: last)
        case .month:
            guard let month = MonthKey(dayKey: dayKey),
                  let last = DayKey.adding(-1, to: month.adding(1).firstDayKey, in: timeZone) else { return nil }
            return DayRange(first: month.firstDayKey, last: last)
        case .year:
            guard let month = MonthKey(dayKey: dayKey) else { return nil }
            return DayRange(first: String(format: "%04d-01-01", month.year),
                            last: String(format: "%04d-12-31", month.year))
        }
    }

    /// The whole period before the one holding `dayKey`.
    public static func previous(of period: Period, containing dayKey: String,
                                in timeZone: TimeZone = .current) -> DayRange? {
        guard let current = range(of: period, containing: dayKey, in: timeZone),
              let before = DayKey.adding(-1, to: current.first, in: timeZone) else { return nil }
        return range(of: period, containing: before, in: timeZone)
    }
}
