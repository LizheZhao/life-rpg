import Foundation

/// One local notification to queue.
public struct PlannedNotification: Equatable, Sendable {
    public enum Kind: String, Sendable { case morning, journal }

    public var kind: Kind
    /// `"<kind>-<dayKey>"`: stable, so queuing again replaces rather than doubles.
    public var id: String
    public var fireDate: Date
    public var title: String
    public var body: String
}

/// Which local notifications to queue.
///
/// A local notification cannot look at the store when it fires, so "don't remind me, I already
/// wrote today" is done the only way it can be: the queue is planned again whenever the app comes
/// forward or goes away, from what is true then. Writing and then leaving removes tonight's
/// reminder before it can fire. Only pure rules live here; turning an item into a
/// `UNNotificationRequest`, and asking for permission, is the app's.
public enum NotificationPlan {
    public struct Settings: Equatable, Sendable {
        public var journal: Bool
        public var morning: Bool
        /// Minutes after midnight, held to `morningRange`.
        public var morningMinute: Int
        /// Minutes after midnight, held to `eveningRange`.
        public var eveningMinute: Int

        public init(journal: Bool = false, morning: Bool = false,
                    morningMinute: Int = defaultMorningMinute, eveningMinute: Int = defaultEveningMinute) {
            self.journal = journal; self.morning = morning
            self.morningMinute = NotificationPlan.clamp(morningMinute, to: NotificationPlan.morningRange)
            self.eveningMinute = NotificationPlan.clamp(eveningMinute, to: NotificationPlan.eveningRange)
        }
    }

    /// The morning note goes after the app day has started (05:00) and before noon.
    public static let morningRange = (LifeCalendar.dayStartHour * 60)...(12 * 60 - 1)
    /// The evening nudge stays on the same calendar date as the day it is about, so from noon to
    /// 23:59: a time after midnight would fall on the next date while the app day is still the old one.
    public static let eveningRange = (12 * 60)...(24 * 60 - 1)
    public static let defaultMorningMinute = 8 * 60
    public static let defaultEveningMinute = JournalEntryToday.cardStartHour * 60

    static func clamp(_ minute: Int, to range: ClosedRange<Int>) -> Int {
        min(max(minute, range.lowerBound), range.upperBound)
    }

    /// How many days ahead are queued. Two a day stay far under the 64 pending iOS keeps.
    public static let horizonDays = 14

    public static func plan(now: Date, timeZone: TimeZone = .current, settings: Settings,
                            todayWritten: Bool, routineCounts: [String: Int],
                            days: Int = horizonDays) -> [PlannedNotification] {
        let cal = LifeCalendar.gregorian(timeZone)
        // Notifications fire on the wall clock, so the days are calendar dates; the app day only
        // matters for what has been written (before 05:00 the app day is still yesterday).
        let firstDate = now.calendarDayKey(in: timeZone)
        let appDay = now.dayKey(in: timeZone)
        var items: [PlannedNotification] = []

        for offset in 0..<max(days, 0) {
            guard let date = DayKey.adding(offset, to: firstDate, in: timeZone) else { continue }

            if settings.morning, let fire = fireDate(date, minute: settings.morningMinute, cal: cal, timeZone: timeZone), fire > now {
                items.append(PlannedNotification(kind: .morning, id: "morning-\(date)", fireDate: fire,
                                                 title: "Today", body: morningBody(routines: routineCounts[date] ?? 0)))
            }

            let written = todayWritten && date == appDay
            if settings.journal, !written,
               let fire = fireDate(date, minute: settings.eveningMinute, cal: cal, timeZone: timeZone), fire > now {
                items.append(PlannedNotification(kind: .journal, id: "journal-\(date)", fireDate: fire,
                                                 title: "Write about today",
                                                 body: "A few lines is enough."))
            }
        }
        return items
    }

    /// Quests are drawn when the app opens, so the morning message only says what is already known:
    /// the routines due that day.
    private static func morningBody(routines: Int) -> String {
        switch routines {
        case 0: "Open the app to see what today asks."
        case 1: "1 routine due today."
        default: "\(routines) routines due today."
        }
    }

    private static func fireDate(_ dayKey: String, minute: Int, cal: Calendar, timeZone: TimeZone) -> Date? {
        guard let midnight = DayKey.date(dayKey, in: timeZone) else { return nil }
        return cal.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: midnight)
    }

    /// How many routines come due on each of `days` days from `start`: what the morning message says.
    /// Inactive and archived rows and lighter versions are not scheduled, so `Schedule` leaves them out.
    public static func routineCounts(routines: [RoutineTask], occurrences: [RoutineOccurrence],
                                     from start: String, days: Int = horizonDays,
                                     in timeZone: TimeZone = .current) -> [String: Int] {
        let live = routines.filter { $0.isActive && !$0.isArchived }
        var counts: [String: Int] = [:]
        for offset in 0..<max(days, 0) {
            guard let day = DayKey.adding(offset, to: start, in: timeZone) else { continue }
            counts[day] = Schedule.dueRoutines(live, occurrences: occurrences, on: day, in: timeZone).count
        }
        return counts
    }

    /// Whether the day's entry has anything written in it (a row holding nothing does not count).
    public static func isWritten(_ entry: JournalEntry?) -> Bool {
        guard let entry else { return false }
        return !entry.document.isEmpty
    }
}
