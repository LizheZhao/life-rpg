import Foundation

/// Which `dayKey`s a routine comes due on (`PLAN.md` §4, "Frequency types").
///
/// Pure: the spec plus whatever of the routine's past the spec needs. Only `everyNDays` and
/// `everyNWeeksOnWeekday` look at the past at all; the calendar kinds are fixed dates.
public enum Schedule {
    /// A missed occurrence stays open for days 1…3 and is auto-skipped on day 4 (`PLAN.md` §4,
    /// "Overdue penalty"). So an unfinished round ends `roundDays` after its due day.
    public static let roundDays = 3

    /// The part of a routine's past that decides the next due date.
    public struct History: Equatable, Sendable {
        /// `everyNDays` counts from here.
        public var lastCompletedDayKey: String?
        /// Due day of the newest occurrence, and whether it was completed. An unfinished one keeps
        /// its round open (`everyNDays` doesn't come due again while it is still on the page),
        /// and once skipped the round is over and the count restarts from the skip day — a
        /// skipped round is not chased every day after.
        public var latestDueDayKey: String?
        public var latestCompleted: Bool
        /// `everyNWeeksOnWeekday` only: the week of the routine's first completion. Nil = never
        /// completed, and the routine comes due every week until it is.
        public var anchorWeekKey: String?

        public init(lastCompletedDayKey: String? = nil, latestDueDayKey: String? = nil,
                    latestCompleted: Bool = false, anchorWeekKey: String? = nil) {
            self.lastCompletedDayKey = lastCompletedDayKey
            self.latestDueDayKey = latestDueDayKey
            self.latestCompleted = latestCompleted
            self.anchorWeekKey = anchorWeekKey
        }
    }

    public static func isDue(_ spec: FrequencySpec, on dayKey: String,
                             history: History = History(),
                             in timeZone: TimeZone = .current) -> Bool {
        guard let weekday = DayKey.weekday(of: dayKey, in: timeZone),
              let (day, monthLength) = dayOfMonth(dayKey, in: timeZone) else { return false }

        switch spec {
        case .weekly(let days):
            return days.contains(weekday)

        case .monthly(let wanted):
            // The 31st in a 30-day month (or February) falls back to the month's last day.
            return day == min(wanted, monthLength)

        case .nthWeekdayOfMonth(let n, let wanted):
            guard weekday == wanted else { return false }
            return n == -1 ? day + 7 > monthLength : (day - 1) / 7 + 1 == n

        case .everyNDays(let n):
            var anchor = history.lastCompletedDayKey
            if let due = history.latestDueDayKey, !history.latestCompleted {
                guard let roundEnd = DayKey.adding(roundDays, to: due, in: timeZone) else { return false }
                if dayKey < roundEnd { return false }             // still open on the page
                anchor = max(anchor ?? roundEnd, roundEnd)         // skipped: count from the skip
            }
            guard let anchor else { return true }                  // never done: due right away
            guard let gap = DayKey.daysBetween(anchor, dayKey, in: timeZone) else { return false }
            return gap >= n

        case .everyNWeeksOnWeekday(let n, let wanted):
            guard weekday == wanted else { return false }
            guard let anchor = history.anchorWeekKey else { return true }
            guard let anchorMonday = DayKey.monday(ofWeek: anchor, in: timeZone),
                  let monday = DayKey.monday(of: dayKey, in: timeZone),
                  let days = DayKey.daysBetween(anchorMonday, monday, in: timeZone) else { return false }
            let weeks = days / 7
            return ((weeks % n) + n) % n == 0
        }
    }

    /// The active routines due on `dayKey`, their history read from `occurrences` (only rows
    /// strictly before that day count). A routine whose spec doesn't parse is never due —
    /// `StoreAudit` reports it. One that already has an occurrence on that day — a flexible
    /// routine done ahead — is not due again, and doesn't count toward that day's load. Nor is a
    /// flexible routine whose `weeklyTarget` is already met this week (ahead completions count):
    /// the week is what it is judged on, so the leftover scheduled days are not asked of you.
    public static func dueRoutines(_ routines: [RoutineTask],
                                   occurrences: [RoutineOccurrence],
                                   on dayKey: String,
                                   in timeZone: TimeZone = .current) -> [RoutineTask] {
        var latest: [UUID: RoutineOccurrence] = [:]
        let existing = Set(occurrences.filter { $0.dueDayKey == dayKey }.compactMap(\.routineID))
        let week = DayKey.weekKey(of: dayKey, in: timeZone)
        var doneThisWeek: [UUID: Int] = [:]
        for o in occurrences where o.weekKey == week && o.completedDayKey != nil {
            if let id = o.routineID { doneThisWeek[id, default: 0] += 1 }
        }
        for o in occurrences where o.dueDayKey < dayKey {
            guard let id = o.routineID else { continue }
            if let current = latest[id], current.dueDayKey >= o.dueDayKey { continue }
            latest[id] = o
        }
        return routines.filter { r in
            guard r.isActive, !existing.contains(r.id), let spec = r.frequency else { return false }
            if r.flexibleWithinWeek, doneThisWeek[r.id, default: 0] >= r.weeklyTarget { return false }
            let last = latest[r.id]
            let history = History(lastCompletedDayKey: r.lastCompletedDayKey,
                                  latestDueDayKey: last?.dueDayKey,
                                  latestCompleted: last?.completedDayKey != nil,
                                  anchorWeekKey: r.anchorWeekKey)
            return isDue(spec, on: dayKey, history: history, in: timeZone)
        }
    }

    /// Which day of its round `dayKey` is for an occurrence due on `due`: 1 on the due day, 2–3
    /// overdue, nil before it or from day 4 on (the auto-skip).
    public static func roundDay(due: String, on dayKey: String, in timeZone: TimeZone = .current) -> Int? {
        guard let offset = DayKey.daysBetween(due, dayKey, in: timeZone),
              (0..<roundDays).contains(offset) else { return nil }
        return offset + 1
    }

    /// Fixed-day occurrences from earlier days still open on `dayKey` (round day 2–3, neither
    /// done nor skipped), oldest first — what the today page pins above today's routines.
    /// Flexible routines are never overdue inside their week; see `openThisWeek`.
    public static func overdue(_ occurrences: [RoutineOccurrence], flexible: Set<UUID>,
                               on dayKey: String, in timeZone: TimeZone = .current) -> [RoutineOccurrence] {
        sorted(occurrences.filter { o in
            isOpen(o) && !isFlexible(o, flexible)
                && (roundDay(due: o.dueDayKey, on: dayKey, in: timeZone) ?? 0) >= 2
        })
    }

    /// Flexible occurrences from earlier days of `dayKey`'s week, still open: they can be done
    /// any day up to Sunday at full pay.
    public static func openThisWeek(_ occurrences: [RoutineOccurrence], flexible: Set<UUID>,
                                    on dayKey: String, in timeZone: TimeZone = .current) -> [RoutineOccurrence] {
        let week = DayKey.weekKey(of: dayKey, in: timeZone)
        return sorted(occurrences.filter { o in
            isOpen(o) && isFlexible(o, flexible) && o.dueDayKey < dayKey && o.weekKey == week
        })
    }

    /// A flexible routine that can be done ahead today (`PLAN.md` §4, "Movable within the week").
    public struct Ahead {
        public var routine: RoutineTask
        /// The occurrence still to come this week that doing it now counts as.
        public var nextDueDayKey: String
        public var doneThisWeek: Int
    }

    /// Active flexible routines short of `weeklyTarget` this week, with nothing of theirs open on
    /// the page (an open one is what you tap instead) and a due day still ahead within the week.
    public static func aheadCandidates(_ routines: [RoutineTask], occurrences: [RoutineOccurrence],
                                       on dayKey: String, in timeZone: TimeZone = .current) -> [Ahead] {
        guard let week = DayKey.weekKey(of: dayKey, in: timeZone),
              let monday = DayKey.monday(of: dayKey, in: timeZone),
              let sunday = DayKey.adding(6, to: monday, in: timeZone),
              let tomorrow = DayKey.adding(1, to: dayKey, in: timeZone) else { return [] }
        let laterThisWeek = DayKey.range(from: tomorrow, through: sunday, in: timeZone)

        return routines
            .filter { $0.isActive && $0.flexibleWithinWeek }
            .sorted { $0.text < $1.text }
            .compactMap { r in
                let mine = occurrences.filter { $0.routineID == r.id && $0.weekKey == week }
                let done = mine.filter { $0.completedDayKey != nil }.count
                guard done < r.weeklyTarget,
                      !mine.contains(where: { isOpen($0) && $0.dueDayKey <= dayKey }),
                      let next = laterThisWeek.first(where: { d in
                          !dueRoutines([r], occurrences: occurrences, on: d, in: timeZone).isEmpty
                      }) else { return nil }
                return Ahead(routine: r, nextDueDayKey: next, doneThisWeek: done)
            }
    }

    /// Occurrences completed on `dayKey` against a later due day — what the page lists as done ahead.
    public static func doneAhead(_ occurrences: [RoutineOccurrence], on dayKey: String) -> [RoutineOccurrence] {
        sorted(occurrences.filter { $0.completedDayKey == dayKey && $0.dueDayKey > dayKey })
    }

    /// Skipped and never done — auto on day 4, or at Sunday settlement — newest first.
    public static func backlog(_ occurrences: [RoutineOccurrence]) -> [RoutineOccurrence] {
        occurrences
            .filter { $0.skipped && $0.completedDayKey == nil }
            .sorted { $0.dueDayKey == $1.dueDayKey ? $0.textSnapshot < $1.textSnapshot
                                                   : $0.dueDayKey > $1.dueDayKey }
    }

    static func isOpen(_ o: RoutineOccurrence) -> Bool { o.completedDayKey == nil && !o.skipped }

    static func isFlexible(_ o: RoutineOccurrence, _ flexible: Set<UUID>) -> Bool {
        o.routineID.map(flexible.contains) ?? false
    }

    private static func sorted(_ os: [RoutineOccurrence]) -> [RoutineOccurrence] {
        os.sorted { $0.dueDayKey == $1.dueDayKey ? $0.textSnapshot < $1.textSnapshot
                                                 : $0.dueDayKey < $1.dueDayKey }
    }

    private static func dayOfMonth(_ dayKey: String, in timeZone: TimeZone) -> (Int, Int)? {
        guard let date = DayKey.date(dayKey, in: timeZone) else { return nil }
        let cal = LifeCalendar.gregorian(timeZone)
        guard let length = cal.range(of: .day, in: .month, for: date)?.count else { return nil }
        return (cal.component(.day, from: date), length)
    }
}

extension DayKey {
    /// The Monday of the ISO week a `dayKey` falls in.
    public static func monday(of dayKey: String, in timeZone: TimeZone = .current) -> String? {
        guard let weekday = weekday(of: dayKey, in: timeZone) else { return nil }
        return adding(-((weekday.rawValue + 5) % 7), to: dayKey, in: timeZone)
    }

    /// The Monday of an ISO `weekKey` (`"2026-W38"` → `"2026-09-14"`).
    public static func monday(ofWeek weekKey: String, in timeZone: TimeZone = .current) -> String? {
        let parts = weekKey.split(separator: "-W", omittingEmptySubsequences: false)
        guard parts.count == 2, let year = Int(parts[0]), let week = Int(parts[1]),
              (1...53).contains(week) else { return nil }
        var c = DateComponents()
        c.yearForWeekOfYear = year; c.weekOfYear = week; c.weekday = 2; c.hour = 12
        guard let date = LifeCalendar.iso8601(timeZone).date(from: c),
              date.weekKey(in: timeZone) == weekKey else { return nil }  // W53 of a 52-week year
        return date.dayKey(in: timeZone)
    }
}
