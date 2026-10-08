import Foundation
import SwiftData

/// "Save to library": a task the user typed becomes a quest in the random pool, or a routine on a
/// schedule — a row of their own (`LibraryOrigin.user`) that goes in the backup, since the seed
/// CSVs can't give it back.
///
/// What a routine pays follows from its difficulty, the same midpoints a custom ad-hoc task pays
/// (`AdHoc.basePoints`: easy 10, medium 21, hard 38), so a routine is easy, medium or hard. A quest
/// has no points of its own, its tier's range decides, so a quest can be any of the five tiers: a
/// micro-action joins the pool the T group is drawn from, an epic the pool the weekly epic is drawn
/// from. A routine always counts toward clearing the day. Text is a row's identity (the seed merge
/// and the restore both match on it), so a text already in that table is refused.
public enum LibrarySave {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case emptyText
        /// A row of that table already has these words (case aside).
        case textTaken
        /// A routine pays by its difficulty's midpoint, which only E / M / H have.
        case noDifficulty
        case noWeekday

        public var description: String {
            switch self {
            case .emptyText: "the task needs a description"
            case .textTaken: "the library already has one with these words"
            case .noDifficulty: "a routine is E, M or H"
            case .noWeekday: "pick at least one day"
            }
        }
    }

    /// The tiers the form offers for what is being saved.
    public static func difficulties(for kind: Draft.Kind) -> [Difficulty] {
        switch kind {
        case .quest: [.trivial, .easy, .medium, .hard, .epic]
        case .routine: [.easy, .medium, .hard]
        }
    }

    /// An epic is one a week rather than a daily slot, and the hidden quest is a light bonus: neither
    /// "weekends only" nor "may be the hidden quest" means anything for it.
    public static func allowsHiddenAndWeekend(_ difficulty: Difficulty) -> Bool { difficulty != .epic }

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

        /// How the routine repeats, as the form states it.
        var cadence: Cadence { frequency == .weekly ? .weekly(Array(days)) : .monthly(position, monthlyWeekday) }
        /// "Times a week" only means something for a flexible weekly routine.
        var timesToSave: Int? { frequency == .weekly && flexible ? timesPerWeek : nil }

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
                return .routine(try saveRoutine(text: text,
                                                .init(difficulty: difficulty, every: cadence, flexible: flexible,
                                                      timesPerWeek: timesToSave),
                                                in: context))
            }
        }
    }

    @discardableResult
    public static func saveQuest(text: String, _ settings: QuestSettings,
                                 in context: ModelContext) throws -> QuestTemplate {
        let text = try trimmed(text)
        guard try !context.fetch(FetchDescriptor<QuestTemplate>()).contains(where: { !$0.isArchived && same($0.text, text) }) else {
            throw Failure.textTaken
        }
        let row = QuestTemplate()
        row.text = text
        row.difficulty = settings.difficulty
        // Whatever the form held when the tier was switched, an epic carries neither.
        let free = allowsHiddenAndWeekend(settings.difficulty)
        row.hiddenEligible = free && settings.hiddenEligible
        row.weekendOnly = free && settings.weekendOnly
        row.origin = .user
        context.insert(row)
        try save(row, in: context)
        return row
    }

    @discardableResult
    public static func saveRoutine(text: String, _ settings: RoutineSettings,
                                   in context: ModelContext) throws -> RoutineTask {
        let text = try checked(text, difficulty: settings.difficulty)
        guard try !context.fetch(FetchDescriptor<RoutineTask>()).contains(where: { !$0.isArchived && same($0.text, text) }) else {
            throw Failure.textTaken
        }
        let row = RoutineTask()
        row.text = text
        row.difficulty = settings.difficulty
        row.basePoints = AdHoc.basePoints(for: settings.difficulty) ?? row.basePoints
        row.countsForClear = true
        row.origin = .user
        try apply(settings.every, flexible: settings.flexible, timesPerWeek: settings.timesPerWeek, to: row)

        context.insert(row)
        try save(row, in: context)
        return row
    }

    /// What a cadence comes to on a routine row. Worked out first and written after, so a cadence
    /// that cannot be read leaves the row as it was.
    struct Resolved: Equatable {
        var kind: RecurrenceKind
        var spec: String
        var weeklyTarget: Int
    }

    static func resolve(_ every: Cadence, flexible: Bool, timesPerWeek: Int?) throws -> Resolved {
        let resolved: Resolved
        switch every {
        case .weekly(let days):
            let days = Array(Set(days)).sorted()
            guard !days.isEmpty else { throw Failure.noWeekday }
            // Fixed asks for every day chosen; flexible for as many as were said, within them.
            resolved = Resolved(kind: .weekly, spec: days.map(\.code).joined(separator: ","),
                                weeklyTarget: flexible ? min(max(timesPerWeek ?? days.count, 1), days.count) : days.count)
        case .monthly(let position, let weekday):
            resolved = Resolved(kind: .nthWeekdayOfMonth, spec: "\(position == .first ? 1 : -1):\(weekday.code)",
                                weeklyTarget: 1)
        }
        // The same reading the CSV import gives a spec: what is saved is what the schedule can read.
        _ = try FrequencySpec.parse(kind: resolved.kind, spec: resolved.spec)
        return resolved
    }

    /// Writes a cadence onto a routine row. Saving a new routine and editing an old one's schedule
    /// both go through here, so the two cannot disagree about what a choice means.
    static func apply(_ every: Cadence, flexible: Bool, timesPerWeek: Int?, to row: RoutineTask) throws {
        let resolved = try resolve(every, flexible: flexible, timesPerWeek: timesPerWeek)
        row.kind = resolved.kind
        row.spec = resolved.spec
        row.weeklyTarget = resolved.weeklyTarget
        row.flexibleWithinWeek = flexible
    }

    private static func trimmed(_ text: String) throws -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure.emptyText }
        return text
    }

    private static func checked(_ text: String, difficulty: Difficulty) throws -> String {
        let text = try trimmed(text)
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
