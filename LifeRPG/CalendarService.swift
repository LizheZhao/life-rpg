import EventKit
import Foundation
import LifeRPGCore

/// Reads the calendars the workout detection watches (`PLAN.md` §5). Which events count is
/// `WorkoutFilter` in Core; this only fetches them. iOS 17+ needs Full Access to read events.
final class CalendarService {
    struct Info: Identifiable {
        let id: String
        let title: String
        /// The account the calendar lives in (iCloud, Gmail, ...), to tell same-named ones apart.
        let source: String
    }

    private let store = EKEventStore()

    static var authorization: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }
    static var hasAccess: Bool { authorization == .fullAccess }

    @discardableResult
    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    /// Event calendars, for the picker on the workout detection page.
    func calendars() -> [Info] {
        guard Self.hasAccess else { return [] }
        return store.calendars(for: .event)
            .map { Info(id: $0.calendarIdentifier, title: $0.title, source: $0.source?.title ?? "") }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
    }

    /// Events in the selected calendars between `from` and `to`. Empty without access or with
    /// nothing selected. Reading every calendar is safe because `WorkoutFilter` still requires a
    /// keyword in the title.
    func events(selection: CalendarSelection, from: Date, to: Date) -> [CalendarEvent] {
        guard Self.hasAccess else { return [] }
        let scope: [EKCalendar]?
        switch selection {
        case .none:
            return []
        case .all:
            scope = nil
        case .some(let ids):
            // A calendar that was deleted since it was picked is skipped, not an error.
            let found = ids.compactMap { store.calendar(withIdentifier: $0) }
            guard !found.isEmpty else { return [] }
            scope = found
        }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: scope)
        return store.events(matching: predicate).map {
            CalendarEvent(calendarID: $0.calendar.calendarIdentifier, title: $0.title ?? "",
                          start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay)
        }
    }
}
