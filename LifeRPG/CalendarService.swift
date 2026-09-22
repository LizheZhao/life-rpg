import EventKit
import Foundation
import LifeRPGCore

/// Reads the calendar the workout Shortcut writes to (`PLAN.md` §5). Which events count is
/// `WorkoutFilter` in Core; this only fetches them. iOS 17+ needs Full Access to read events.
final class CalendarService {
    private let store = EKEventStore()

    static var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    @discardableResult
    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    /// Event calendars as (identifier, title), for the picker on the debug page.
    func calendars() -> [(id: String, title: String)] {
        guard Self.hasAccess else { return [] }
        return store.calendars(for: .event)
            .map { ($0.calendarIdentifier, $0.title) }
            .sorted { $0.title < $1.title }
    }

    /// Events in the chosen calendar between `from` and `to`. Empty without access or without a
    /// chosen calendar — never every calendar, so a meeting can't pass for a workout.
    func events(calendarID: String, from: Date, to: Date) -> [CalendarEvent] {
        guard Self.hasAccess, !calendarID.isEmpty,
              let calendar = store.calendar(withIdentifier: calendarID) else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: [calendar])
        return store.events(matching: predicate).map {
            CalendarEvent(calendarID: $0.calendar.calendarIdentifier, title: $0.title ?? "",
                          start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay)
        }
    }
}
