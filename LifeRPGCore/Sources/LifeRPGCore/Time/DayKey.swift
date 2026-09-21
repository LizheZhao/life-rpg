import Foundation

/// Fixed calendars. Never `Calendar.current`: its `firstWeekday` and even its calendar system
/// follow the user's region settings, which would move week boundaries (and therefore Sunday
/// settlement and the epic week) the moment the region changes.
public enum LifeCalendar {
    /// Gregorian, for `dayKey`. The time zone is read per call so a travel-time change applies.
    public static func gregorian(_ timeZone: TimeZone = .current) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    /// ISO 8601, for `weekKey`: Monday-start weeks, week 1 is the one containing the first Thursday.
    public static func iso8601(_ timeZone: TimeZone = .current) -> Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = timeZone
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }
}

extension Date {
    /// `"2026-09-17"` — the local calendar day.
    public func dayKey(in timeZone: TimeZone = .current) -> String {
        let c = LifeCalendar.gregorian(timeZone).dateComponents([.year, .month, .day], from: self)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// `"2026-W38"` — the ISO week. Note the year is the ISO week-year, so 2027-01-01 is `2026-W53`.
    public func weekKey(in timeZone: TimeZone = .current) -> String {
        let c = LifeCalendar.iso8601(timeZone).dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear!, c.weekOfYear!)
    }

    public var dayKey: String { dayKey(in: .current) }
    public var weekKey: String { weekKey(in: .current) }
}

/// String helpers for the `dayKey` / `weekKey` business keys. Business logic compares these
/// strings; `Date` is only ever an input.
public enum DayKey {
    /// Noon on that day, which keeps the round trip intact across DST transitions that happen at
    /// midnight (Brazil, Chile, Cuba …). Returns nil on a malformed key or a date that doesn't exist.
    public static func date(_ dayKey: String, in timeZone: TimeZone = .current) -> Date? {
        let parts = dayKey.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        let cal = LifeCalendar.gregorian(timeZone)
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = 12
        guard let date = cal.date(from: comps),
              cal.component(.day, from: date) == d, cal.component(.month, from: date) == m
        else { return nil }   // rejects 2026-02-30 and friends, which Calendar would roll over
        return date
    }

    public static func isValid(_ dayKey: String, in timeZone: TimeZone = .current) -> Bool {
        date(dayKey, in: timeZone) != nil
    }

    /// The ISO week a `dayKey` belongs to.
    public static func weekKey(of dayKey: String, in timeZone: TimeZone = .current) -> String? {
        date(dayKey, in: timeZone)?.weekKey(in: timeZone)
    }

    /// Gregorian weekday of a `dayKey`.
    public static func weekday(of dayKey: String, in timeZone: TimeZone = .current) -> Weekday? {
        guard let date = date(dayKey, in: timeZone) else { return nil }
        return Weekday(rawValue: LifeCalendar.gregorian(timeZone).component(.weekday, from: date))
    }

    public static func isWeekend(_ dayKey: String, in timeZone: TimeZone = .current) -> Bool {
        guard let w = weekday(of: dayKey, in: timeZone) else { return false }
        return w == .saturday || w == .sunday
    }

    /// `offset` days later (or earlier). Nil only if the key itself is malformed.
    public static func adding(_ offset: Int, to dayKey: String, in timeZone: TimeZone = .current) -> String? {
        guard let date = date(dayKey, in: timeZone),
              let moved = LifeCalendar.gregorian(timeZone).date(byAdding: .day, value: offset, to: date)
        else { return nil }
        return moved.dayKey(in: timeZone)
    }

    /// Every day strictly after `start` up to and including `end`; empty when `end <= start`.
    /// This is the catch-up loop's day list.
    public static func range(after start: String, through end: String,
                             in timeZone: TimeZone = .current) -> [String] {
        guard isValid(start, in: timeZone), isValid(end, in: timeZone) else { return [] }
        var out: [String] = []
        var cursor = start
        while cursor < end, out.count < 3660 {          // ~10 years, guards against a bad key
            guard let next = adding(1, to: cursor, in: timeZone) else { break }
            out.append(next)
            cursor = next
        }
        return out
    }

    /// Every day from `start` through `end`, inclusive at **both** ends; empty when `end < start`.
    /// This is the catch-up loop's day list: it has to re-include the last day the app saw, because
    /// that day was generated but not yet settled.
    public static func range(from start: String, through end: String,
                             in timeZone: TimeZone = .current) -> [String] {
        guard isValid(start, in: timeZone), isValid(end, in: timeZone), start <= end else { return [] }
        var out = [start]
        var cursor = start
        while cursor < end, out.count < 3660 {
            guard let next = adding(1, to: cursor, in: timeZone) else { break }
            out.append(next)
            cursor = next
        }
        return out
    }

    /// Whole days between two keys, `to - from`.
    public static func daysBetween(_ from: String, _ to: String, in timeZone: TimeZone = .current) -> Int? {
        guard let a = date(from, in: timeZone), let b = date(to, in: timeZone) else { return nil }
        return LifeCalendar.gregorian(timeZone).dateComponents([.day], from: a, to: b).day
    }
}
