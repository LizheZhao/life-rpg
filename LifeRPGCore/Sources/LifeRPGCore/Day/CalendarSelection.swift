import Foundation

/// Which calendars the workout filter reads (`PLAN.md` §5). Reading more calendars never loosens
/// what counts as a workout: `WorkoutFilter` still wants a keyword in the title.
public enum CalendarSelection: Equatable, Sendable {
    case none
    case some(Set<String>)
    case all

    /// Stored as one string so `@AppStorage` can hold it: `""` is none, `"*"` is all, anything
    /// else is calendar IDs joined by commas. The key predates multi-select and held one bare
    /// calendar ID, which therefore reads as `some([that ID])` with no migration.
    public init(setting: String) {
        let trimmed = setting.trimmingCharacters(in: .whitespaces)
        if trimmed == "*" {
            self = .all
            return
        }
        let ids = trimmed.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        self = ids.isEmpty ? .none : .some(Set(ids))
    }

    /// An ID containing a comma can't be told apart from two IDs, so it is left out; EventKit
    /// identifiers are UUIDs and never contain one.
    public var setting: String {
        switch self {
        case .none: ""
        case .all: "*"
        case .some(let ids): ids.filter { !$0.contains(",") }.sorted().joined(separator: ",")
        }
    }

    public func contains(_ calendarID: String) -> Bool {
        switch self {
        case .none: false
        case .all: true
        case .some(let ids): ids.contains(calendarID)
        }
    }

    /// Adds or removes one calendar. `all` has no individual calendars to flip, so it stays.
    public func toggling(_ calendarID: String) -> CalendarSelection {
        switch self {
        case .all: return self
        case .none: return .some([calendarID])
        case .some(var ids):
            if !ids.insert(calendarID).inserted { ids.remove(calendarID) }
            return ids.isEmpty ? .none : .some(ids)
        }
    }
}
