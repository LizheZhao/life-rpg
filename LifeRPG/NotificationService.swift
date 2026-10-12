import Foundation
import LifeRPGCore
import SwiftData
import UserNotifications

/// Local reminders: asks for permission when the user switches one on, and keeps the queue equal
/// to what `NotificationPlan` says. The queue is rebuilt (never appended to) whenever the app
/// comes forward, goes away or a setting changes, so "I already wrote today" removes tonight's
/// reminder as soon as the app is left. Notifications fire on the real clock; Debug time travel
/// does not move them.
@MainActor
enum NotificationService {
    static let journalKey = "notify.journal"
    static let morningKey = "notify.morning"
    static let morningMinuteKey = "notify.morningMinute"
    static let eveningMinuteKey = "notify.eveningMinute"
    /// Before the times took minutes the morning was stored as a whole hour; it is still read, so a
    /// time set back then carries over until the user picks a new one.
    private static let legacyMorningHourKey = "notify.morningHour"

    static var settings: NotificationPlan.Settings {
        let d = UserDefaults.standard
        return .init(journal: d.bool(forKey: journalKey), morning: d.bool(forKey: morningKey),
                     morningMinute: morningMinute, eveningMinute: eveningMinute)
    }

    static var morningMinute: Int {
        let d = UserDefaults.standard
        if let minute = d.object(forKey: morningMinuteKey) as? Int { return minute }
        if let hour = d.object(forKey: legacyMorningHourKey) as? Int { return hour * 60 }
        return NotificationPlan.defaultMorningMinute
    }

    static var eveningMinute: Int {
        UserDefaults.standard.object(forKey: eveningMinuteKey) as? Int ?? NotificationPlan.defaultEveningMinute
    }

    static func authorization() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Shows the system prompt the first time; afterwards answers from what the user decided.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await authorization() {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    /// Switches one reminder (`journalKey` or `morningKey`). Switching off needs no permission;
    /// switching on asks, and a refusal leaves it off. Returns whether the reminder is now on.
    @discardableResult
    static func set(_ key: String, on: Bool, in context: ModelContext) async -> Bool {
        let allowed = on ? await requestAuthorization() : false
        UserDefaults.standard.set(allowed, forKey: key)
        await reschedule(in: context)
        return allowed
    }

    /// Replaces this app's pending reminders with the plan for right now.
    static func reschedule(in context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        let ours = await center.pendingNotificationRequests().map(\.identifier).filter(isOurs)
        center.removePendingNotificationRequests(withIdentifiers: ours)

        let wanted = settings
        guard wanted.journal || wanted.morning else { return }
        switch await authorization() {
        case .authorized, .provisional, .ephemeral: break
        default: return
        }

        let now = Date()
        let appDay = now.dayKey
        let entries = (try? context.fetch(FetchDescriptor<JournalEntry>())) ?? []
        let routines = (try? context.fetch(FetchDescriptor<RoutineTask>())) ?? []
        let occurrences = (try? context.fetch(FetchDescriptor<RoutineOccurrence>())) ?? []
        let plan = NotificationPlan.plan(
            now: now, settings: wanted,
            todayWritten: NotificationPlan.isWritten(entries.first { $0.dayKey == appDay }),
            routineCounts: NotificationPlan.routineCounts(routines: routines, occurrences: occurrences,
                                                          from: now.calendarDayKey(in: .current)))
        for item in plan {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }

    private static func isOurs(_ id: String) -> Bool { id.hasPrefix("morning-") || id.hasPrefix("journal-") || id == "debug-test" }

    /// What is queued, soonest first, for the Debug page.
    static func pending() async -> [(id: String, fires: Date?)] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
            .map { ($0.identifier, ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                    ?? ($0.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()) }
            .sorted { ($0.1 ?? .distantFuture) < ($1.1 ?? .distantFuture) }
    }

    /// Fires one in `seconds`, so the look of a reminder can be checked without waiting for 20:00.
    static func sendTest(after seconds: TimeInterval = 5) async {
        guard await requestAuthorization() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Write about today"
        content.body = "A few lines is enough. Pull in a question if you want one."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "debug-test", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }
}
