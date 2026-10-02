import Foundation
import SwiftData

/// One thing the auto-verifier completed, identified so two snapshots can be diffed.
public struct AutoVerifiedItem: Equatable, Hashable, Sendable {
    public var id: UUID
    public var title: String

    public init(id: UUID, title: String) {
        self.id = id
        self.title = title
    }
}

extension AutoVerify {
    /// Today's quests and routines that were completed by auto-verification (not by a tap).
    /// Snapshot it before and after a check to tell what that check verified.
    public static func verifiedItems(on dayKey: String, in context: ModelContext) throws -> [AutoVerifiedItem] {
        let routines = try DayService.occurrences(dueOn: dayKey, in: context)
            .filter { $0.completedDayKey == dayKey && $0.sourceType == .healthKit }
            .map { AutoVerifiedItem(id: $0.id, title: $0.displayText) }
        let quests = try DayService.quests(on: dayKey, in: context)
            .filter { $0.completedAt != nil && !$0.replaced && $0.sourceType == .healthKit }
            .map { AutoVerifiedItem(id: $0.id, title: $0.textSnapshot) }
        return routines + quests
    }
}

/// What "Check for workouts now" reports (`PLAN.md` §5): what it read, what counted, what it
/// verified, and when nothing was detected, the first reason in the chain that explains it. Pure
/// data; the view only renders it.
public struct WorkoutCheck: Equatable, Sendable {
    /// The first reason in the chain that explains why nothing counted. Order matters: no access
    /// hides every later cause, no calendar or keyword hides "no events".
    public enum Outcome: Equatable, Sendable {
        case noCalendarAccess, noCalendarsSelected, noKeywords, noEventsInWindow, noneMatched, matched
    }

    public struct Unmatched: Equatable, Sendable {
        public var title: String
        public var isAllDay: Bool

        public init(title: String, isAllDay: Bool) {
            self.title = title
            self.isAllDay = isAllDay
        }
    }

    public static let unmatchedShown = 3

    public var checkedAt: Date
    public var windowStart: Date
    public var outcome: Outcome
    public var eventsRead: Int
    public var matched: Int
    /// Newest first, at most `unmatchedShown`: events the filter rejected, so the user can see why.
    public var unmatched: [Unmatched]
    public var workoutMinutes: [Int]
    public var mindfulMinutes: Int
    /// Titles of today's items this check verified.
    public var verified: [String]

    public static func make(checkedAt: Date, windowStart: Date, calendarAccess: Bool,
                            filter: WorkoutFilter, events: [CalendarEvent],
                            todayEvidence: DayEvidence,
                            before: [AutoVerifiedItem], after: [AutoVerifiedItem]) -> WorkoutCheck {
        let hits = events.filter(filter.matches)
        let misses = events.filter { !filter.matches($0) }
            .sorted { $0.start > $1.start }
            .prefix(unmatchedShown)
            .map { Unmatched(title: $0.title, isAllDay: $0.isAllDay) }
        let words = filter.keywords.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        let outcome: Outcome =
            if !calendarAccess { .noCalendarAccess }
            else if filter.calendars == .none { .noCalendarsSelected }
            else if words.isEmpty { .noKeywords }
            else if events.isEmpty { .noEventsInWindow }
            else if hits.isEmpty { .noneMatched }
            else { .matched }

        let already = Set(before.map(\.id))
        return WorkoutCheck(checkedAt: checkedAt, windowStart: windowStart, outcome: outcome,
                            eventsRead: events.count, matched: hits.count, unmatched: Array(misses),
                            workoutMinutes: todayEvidence.workoutMinutes.map { Int($0) },
                            mindfulMinutes: Int(todayEvidence.mindfulMinutes),
                            verified: after.filter { !already.contains($0.id) }.map(\.title))
    }
}
