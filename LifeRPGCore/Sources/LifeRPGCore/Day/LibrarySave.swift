import Foundation
import SwiftData

/// "Save to library": a task the user typed becomes a quest in the random pool, or a routine on a
/// schedule — a row of their own (`LibraryOrigin.user`) that goes in the backup, since the seed
/// CSVs can't give it back.
///
/// What it pays follows from its difficulty, the same midpoints a custom ad-hoc task pays
/// (`AdHoc.basePoints`: easy 10, medium 21, hard 38); a quest has no points of its own, its tier's
/// range decides. A routine always counts toward clearing the day. Text is a row's identity (the
/// seed merge and the restore both match on it), so a text already in that table is refused.
public enum LibrarySave {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case emptyText
        /// A row of that table already has these words (case aside).
        case textTaken
        /// Only E / M / H have a range to pay by.
        case noDifficulty
        case noWeekday

        public var description: String {
            switch self {
            case .emptyText: "the task needs a description"
            case .textTaken: "the library already has one with these words"
            case .noDifficulty: "pick E, M or H"
            case .noWeekday: "pick at least one day"
            }
        }
    }

    public struct QuestSettings: Equatable, Sendable {
        public var difficulty: Difficulty
        /// May be drawn as the day's hidden quest.
        public var hiddenEligible: Bool
        /// Left out of the pool Monday to Friday.
        public var weekendOnly: Bool

        public init(difficulty: Difficulty, hiddenEligible: Bool = false, weekendOnly: Bool = false) {
            self.difficulty = difficulty
            self.hiddenEligible = hiddenEligible
            self.weekendOnly = weekendOnly
        }
    }

    public enum MonthPosition: Equatable, Sendable { case first, last }

    /// When a routine comes due: the due day follows from the choice, nothing else is asked.
    public enum Cadence: Equatable, Sendable {
        /// On these weekdays, every week.
        case weekly([Weekday])
        /// The first or the last such weekday of every month.
        case monthly(MonthPosition, Weekday)
    }

    public struct RoutineSettings: Equatable, Sendable {
        public var difficulty: Difficulty
        public var every: Cadence
        /// Fixed asks for it on the day it is due, and charges the ladder after; flexible lets any
        /// day of the due week do, and settles on Sunday (`Overdue.weekly`).
        public var flexible: Bool
        /// Flexible weekly only: how many of the due days have to be done. Between one and the
        /// number of days; unsaid means all of them.
        public var timesPerWeek: Int?

        public init(difficulty: Difficulty, every: Cadence, flexible: Bool = false, timesPerWeek: Int? = nil) {
            self.difficulty = difficulty
            self.every = every
            self.flexible = flexible
            self.timesPerWeek = timesPerWeek
        }
    }

    /// The "Save to library" form as it is filled in: what to save it as and how it repeats. The
    /// view edits this and renders `problem`; turning it into a row is `save`.
    public struct Draft: Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case quest, routine }
        public enum Frequency: Equatable, Sendable { case weekly, monthly }

        public var kind: Kind = .quest
        // A quest.
        public var hiddenEligible = false
        public var weekendOnly = false
        // A routine.
        public var frequency: Frequency = .weekly
        public var days: Set<Weekday> = []
        public var position: MonthPosition = .last
        /// Saturday, like the library's own monthly routines.
        public var monthlyWeekday: Weekday = .saturday
        public var flexible = false
        public var timesPerWeek = 1

        public init() {}

        /// What stops it being saved yet; nil when it can be.
        public var problem: Failure? {
            kind == .routine && frequency == .weekly && days.isEmpty ? .noWeekday : nil
        }

        /// How many of the chosen days a flexible week can ask for.
        public var timesRange: ClosedRange<Int> { 1...max(days.count, 1) }

        public enum Saved {
            case quest(QuestTemplate)
            case routine(RoutineTask)
        }

        @discardableResult
        public func save(text: String, difficulty: Difficulty, in context: ModelContext) throws -> Saved {
            if let problem { throw problem }
            switch kind {
            case .quest:
                return .quest(try saveQuest(text: text, .init(difficulty: difficulty, hiddenEligible: hiddenEligible,
                                                              weekendOnly: weekendOnly), in: context))
            case .routine:
                let every: Cadence = frequency == .weekly ? .weekly(Array(days)) : .monthly(position, monthlyWeekday)
                return .routine(try saveRoutine(text: text,
                                                .init(difficulty: difficulty, every: every, flexible: flexible,
                                                      timesPerWeek: frequency == .weekly && flexible ? timesPerWeek : nil),
                                                in: context))
            }
        }
    }

    @discardableResult
    public static func saveQuest(text: String, _ settings: QuestSettings,
                                 in context: ModelContext) throws -> QuestTemplate {
        let text = try checked(text, difficulty: settings.difficulty)
        guard try !context.fetch(FetchDescriptor<QuestTemplate>()).contains(where: { same($0.text, text) }) else {
            throw Failure.textTaken
        }
        let row = QuestTemplate()
        row.text = text
        row.difficulty = settings.difficulty
        row.hiddenEligible = settings.hiddenEligible
        row.weekendOnly = settings.weekendOnly
        row.origin = .user
        context.insert(row)
        try save(row, in: context)
        return row
    }

    @discardableResult
    public static func saveRoutine(text: String, _ settings: RoutineSettings,
                                   in context: ModelContext) throws -> RoutineTask {
        let text = try checked(text, difficulty: settings.difficulty)
        guard try !context.fetch(FetchDescriptor<RoutineTask>()).contains(where: { same($0.text, text) }) else {
            throw Failure.textTaken
        }
        let row = RoutineTask()
        row.text = text
        row.difficulty = settings.difficulty
        row.basePoints = AdHoc.basePoints(for: settings.difficulty) ?? row.basePoints
        row.countsForClear = true
        row.flexibleWithinWeek = settings.flexible
        row.origin = .user

        switch settings.every {
        case .weekly(let days):
            let days = Array(Set(days)).sorted()
            guard !days.isEmpty else { throw Failure.noWeekday }
            row.kind = .weekly
            row.spec = days.map(\.code).joined(separator: ",")
            // Fixed asks for every day chosen; flexible for as many as were said, within them.
            row.weeklyTarget = settings.flexible
                ? min(max(settings.timesPerWeek ?? days.count, 1), days.count) : days.count
        case .monthly(let position, let weekday):
            row.kind = .nthWeekdayOfMonth
            row.spec = "\(position == .first ? 1 : -1):\(weekday.code)"
            row.weeklyTarget = 1
        }
        // The same reading the CSV import gives a spec: what is saved is what the schedule can read.
        _ = try FrequencySpec.parse(kind: row.kind, spec: row.spec)

        context.insert(row)
        try save(row, in: context)
        return row
    }

    private static func checked(_ text: String, difficulty: Difficulty) throws -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure.emptyText }
        guard AdHoc.basePoints(for: difficulty) != nil else { throw Failure.noDifficulty }
        return text
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(b) == .orderedSame
    }

    private static func save(_ row: some PersistentModel, in context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.delete(row)
            throw error
        }
    }
}
