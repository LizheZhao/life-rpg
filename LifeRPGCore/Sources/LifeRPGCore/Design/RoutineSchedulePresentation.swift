import Foundation

/// What the Library says about when a routine comes up: which group it sits in, the pill, the
/// Monday-first week strip and the sentences. Words follow `Schedule` (which days), `Overdue`
/// (what a miss costs) and `Degrade` (lighter versions); the view only renders them.
public struct RoutineSchedulePresentation: Equatable, Sendable {
    /// Raw values are the keys the Library remembers expanded sections under.
    public enum Group: String, CaseIterable, Comparable, Sendable {
        case setDays, flexible, everyNDays, monthly, lighterVersion, unscheduled

        public var title: String {
            switch self {
            case .setDays: "Set days"
            case .flexible: "Flexible"
            case .everyNDays: "Every few days"
            case .monthly: "Monthly or longer"
            case .lighterVersion: "Lighter versions"
            case .unscheduled: "Not scheduled"
            }
        }

        public static func < (a: Group, b: Group) -> Bool {
            allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
        }
    }

    /// `days` fills the cells of the days it comes up on, `anyDay` outlines all seven (a flexible
    /// routine is judged by its week), `none` draws no strip at all.
    public enum Strip: Equatable, Sendable { case days, anyDay, none }

    public struct Row {
        public let routine: RoutineTask
        public let schedule: RoutineSchedulePresentation
    }

    public struct Section {
        public let group: Group
        public let rows: [Row]
    }

    public let group: Group
    public let strip: Strip
    /// Monday first. The days a weekly spec names, whether or not the strip fills them.
    public let weekdays: [Bool]
    public let summary: String
    /// When it comes up, in words. This is also what VoiceOver reads.
    public let sentence: String
    /// Nil for a routine that has no schedule of its own.
    public let weeklyTarget: Int?
    public let countsForClear: Bool
    /// Only `everyNWeeksOnWeekday` (every 2nd week or slower) has one.
    public let anchorWeekKey: String?
    /// Whether the routine counts its weeks from an anchor, so the page says so even before one is set.
    public let usesAnchorWeek: Bool

    private let order: [Int]

    public init(kind: RecurrenceKind, spec: String, weeklyTarget: Int, flexibleWithinWeek: Bool,
                countsForClear: Bool, anchorWeekKey: String?, isLightVersion: Bool) {
        self.countsForClear = countsForClear
        var anchor: String?
        var usesAnchor = false
        let parsed = isLightVersion ? nil : try? FrequencySpec.parse(kind: kind, spec: spec)

        guard let frequency = parsed else {
            group = isLightVersion ? .lighterVersion : .unscheduled
            strip = .none
            weekdays = Array(repeating: false, count: 7)
            summary = isLightVersion ? "Lighter version" : "No schedule"
            sentence = isLightVersion ? "Stands in for the original on low days." : "No schedule."
            self.weeklyTarget = nil
            self.anchorWeekKey = nil
            usesAnchorWeek = false
            order = []
            return
        }

        var days = Array(repeating: false, count: 7)
        var when: String
        let anyDayThatWeek = " Doing it any day that week counts."

        switch frequency {
        case .weekly(let weekdays):
            let sorted = weekdays.sorted { $0.mondayIndex < $1.mondayIndex }
            sorted.forEach { days[$0.mondayIndex] = true }
            if flexibleWithinWeek {
                group = .flexible
                strip = .anyDay
                summary = "\(weeklyTarget)× a week · any day"
                when = "\(Self.times(weeklyTarget)) a week, any day."
                order = [-weeklyTarget]
            } else {
                group = .setDays
                strip = .days
                summary = Self.daysSummary(sorted)
                when = Self.daysSentence(sorted)
                order = [sorted[0].mondayIndex]
            }

        case .everyNWeeksOnWeekday(let n, let weekday) where n == 1:
            days[weekday.mondayIndex] = true
            group = .setDays
            strip = .days
            summary = Self.daysSummary([weekday])
            when = Self.daysSentence([weekday])
            order = [weekday.mondayIndex]

        case .everyNDays(let n):
            group = .everyNDays
            strip = .none
            summary = n == 1 ? "Every day" : "Every \(n) days"
            when = "\(summary) from the last time."
            order = [n]

        case .monthly(let day):
            group = .monthly
            strip = .none
            summary = "Day \(day)"
            when = "Comes up on the \(Self.ordinal(day)) of each month"
                + (day > 28 ? ", or on the last day of a shorter month." : ".")
            order = [0, day]

        case .nthWeekdayOfMonth(let n, let weekday):
            let word = n == -1 ? "last" : Self.ordinalWord(n)
            group = .monthly
            strip = .none
            summary = "\(word.capitalized) \(weekday.fullName)"
            when = "Comes up on the \(word) \(weekday.fullName) of each month."
            order = [1, n == -1 ? 5 : n, weekday.mondayIndex]

        case .everyNWeeksOnWeekday(let n, let weekday):
            group = .monthly
            strip = .none
            summary = "Every \(Self.ordinal(n)) \(weekday.fullName)"
            anchor = anchorWeekKey
            usesAnchor = true
            when = "Every \(Self.ordinal(n)) \(weekday.fullName)."
            order = [2, n, weekday.mondayIndex]
        }

        if flexibleWithinWeek, group != .flexible { when += anyDayThatWeek }
        weekdays = days
        sentence = when
        self.weeklyTarget = weeklyTarget
        self.anchorWeekKey = anchor
        usesAnchorWeek = usesAnchor
    }

    public init(_ routine: RoutineTask, isLightVersion: Bool) {
        self.init(kind: routine.kind, spec: routine.spec, weeklyTarget: routine.weeklyTarget,
                  flexibleWithinWeek: routine.flexibleWithinWeek, countsForClear: routine.countsForClear,
                  anchorWeekKey: routine.anchorWeekKey, isLightVersion: isLightVersion)
    }

    /// Sections in group order, empty ones left out; rows inside each ordered by the group's own
    /// key, then by text. `lightIDs` is `Degrade.versionIDs(in:)` over every routine, because
    /// `shown` may already be narrowed by a search.
    public static func grouped(_ shown: [RoutineTask], lightIDs: Set<UUID>) -> [Section] {
        let rows = shown.map { Row(routine: $0, schedule: RoutineSchedulePresentation($0, isLightVersion: lightIDs.contains($0.id))) }
        return Group.allCases.compactMap { group in
            let inGroup = rows.filter { $0.schedule.group == group }.sorted { a, b in
                if a.schedule.order != b.schedule.order { return a.schedule.order.lexicographicallyPrecedes(b.schedule.order) }
                return a.routine.text.localizedStandardCompare(b.routine.text) == .orderedAscending
            }
            return inGroup.isEmpty ? nil : Section(group: group, rows: inGroup)
        }
    }

    // MARK: words

    /// What a routine pays and what leaving it undone costs, in plain words, for the row's
    /// difficulty control. The numbers are `Scoring`'s: a fixed routine is charged each night it is
    /// still undone (they add up), a flexible one once on Sunday per session short of the week's
    /// target, and one that does not gate the day is never charged.
    public static func difficultyNote(basePoints: Int, flexible: Bool, countsForClear: Bool) -> String {
        let pays = "Pays \(basePoints)."
        switch (flexible, countsForClear) {
        case (false, true):
            let night = (1...3).map { Scoring.overduePenalty(basePoints: basePoints, roundDay: $0) }
            return "\(pays) Skip it and it costs \(night[0]), then \(night[1]), then \(night[2]) on the next two days, then it's gone."
        case (false, false):
            return "\(pays) No penalty. Gone after three days."
        case (true, true):
            return "\(pays) Each session short of the week's target costs \(Scoring.flexibleShortfallPenalty(basePoints: basePoints)) on Sunday."
        case (true, false):
            return "\(pays) No penalty. Gone on Sunday."
        }
    }

    private static func daysSummary(_ days: [Weekday]) -> String {
        days.count == 7 ? "Every day" : days.map(\.shortName).joined(separator: " · ")
    }

    private static func daysSentence(_ days: [Weekday]) -> String {
        days.count == 7 ? "Comes up every day." : "Comes up on \(list(days.map(\.fullName)))."
    }

    private static func list(_ items: [String]) -> String {
        items.count < 2 ? items.joined() : items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }

    private static func times(_ n: Int) -> String {
        switch n {
        case 1: "Once"
        case 2: "Twice"
        default: "\(n) times"
        }
    }

    private static func ordinalWord(_ n: Int) -> String {
        ["first", "second", "third", "fourth"][n - 1]
    }

    private static func ordinal(_ n: Int) -> String {
        let suffix = (11...13).contains(n % 100) ? "th" : ["th", "st", "nd", "rd"][n % 10 < 4 ? n % 10 : 0]
        return "\(n)\(suffix)"
    }
}

extension Weekday {
    /// 0 for Monday … 6 for Sunday: the week as the Library strip draws it.
    fileprivate var mondayIndex: Int { (rawValue + 5) % 7 }

    fileprivate var shortName: String { String(fullName.prefix(3)) }

    fileprivate var fullName: String {
        switch self {
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        }
    }
}
