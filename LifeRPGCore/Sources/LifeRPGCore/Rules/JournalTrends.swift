import Foundation

/// The rules behind the Trends page. Everything here is a pure function of rows the page already
/// holds (`JournalEntryDay`, `DailyQuest` and the like), so a number on the page cannot drift from the
/// journal or the calendar it summarises. Nothing is stored.
public enum JournalTrends {
    /// What the Weeks / Months / Year switch selects.
    public enum Period: String, CaseIterable, Sendable {
        case week, month, year
    }

    /// First and last `dayKey` of a period, both inclusive.
    public struct DayRange: Equatable, Sendable {
        public let first: String
        public let last: String

        public init(first: String, last: String) {
            self.first = first
            self.last = last
        }

        public func contains(_ dayKey: String) -> Bool { first <= dayKey && dayKey <= last }

        /// Every day of the range in order, so a day with nothing in it still has its slot.
        public func days(in timeZone: TimeZone = .current) -> [String] {
            DayKey.range(from: first, through: last, in: timeZone)
        }
    }

    /// The period that holds `dayKey`. Weeks run Monday to Sunday as the month grid's rows do,
    /// months and years are calendar ones. Nil only for a malformed key.
    public static func range(of period: Period, containing dayKey: String,
                             in timeZone: TimeZone = .current) -> DayRange? {
        guard DayKey.isValid(dayKey, in: timeZone) else { return nil }
        switch period {
        case .week:
            // Gregorian weekday: Sunday = 1, so Monday is 0 days back and Sunday 6.
            guard let weekday = DayKey.weekday(of: dayKey, in: timeZone),
                  let first = DayKey.adding(-((weekday.rawValue + 5) % 7), to: dayKey, in: timeZone),
                  let last = DayKey.adding(6, to: first, in: timeZone) else { return nil }
            return DayRange(first: first, last: last)
        case .month:
            guard let month = MonthKey(dayKey: dayKey),
                  let last = DayKey.adding(-1, to: month.adding(1).firstDayKey, in: timeZone) else { return nil }
            return DayRange(first: month.firstDayKey, last: last)
        case .year:
            guard let month = MonthKey(dayKey: dayKey) else { return nil }
            return DayRange(first: String(format: "%04d-01-01", month.year),
                            last: String(format: "%04d-12-31", month.year))
        }
    }
}

extension JournalTrends {
    /// The Trends page's "when and how much": the writing days of one period, plus the all-time
    /// facts (streak, nights written) that a period filter would get wrong.
    public struct Writing {
        /// A week of entries before any pattern means anything. Short entries count.
        public static let unlockNights = 7

        public struct DayWords: Equatable, Sendable {
            public let dayKey: String
            public let words: Int
            /// 0 for a day with no writing, 1 to 3 for the rest, 3 the longest third
            /// (`Year.level(forWords:among:)`), for both the bars and the heat grid.
            public let level: Int
        }

        private let all: [JournalEntryDay]
        private let range: DayRange
        private let timeZone: TimeZone

        /// `days` may be the whole history: the period is cut here.
        public init(days: [JournalEntryDay], range: DayRange, timeZone: TimeZone = .current) {
            self.all = days
            self.range = range
            self.timeZone = timeZone
        }

        private var inRange: [JournalEntryDay] { all.filter { range.contains($0.dayKey) } }

        public var entries: Int { inRange.count }

        public var totalWords: Int { inRange.reduce(0) { $0 + $1.wordCount } }

        /// Over written days, rounded to the nearest word. 0 with none.
        public var averageWords: Int {
            let n = entries
            return n == 0 ? 0 : (totalWords + n / 2) / n
        }

        /// Every day of the period in order, 0 words for a day with none.
        public var wordsByDay: [DayWords] {
            let words = Dictionary(inRange.map { ($0.dayKey, $0.wordCount) }, uniquingKeysWith: +)
            let written = Array(words.values)
            return range.days(in: timeZone).map { key in
                let count = words[key] ?? 0
                return DayWords(dayKey: key, words: count, level: Year.level(forWords: count, among: written))
            }
        }

        /// Consecutive written days ending today, or ending yesterday while today is still unwritten,
        /// so a streak is not lost before the evening.
        public func writingStreak(asOf today: String) -> Int {
            let written = Set(all.map(\.dayKey))
            var cursor = today
            if !written.contains(cursor) {
                guard let yesterday = DayKey.adding(-1, to: today, in: timeZone) else { return 0 }
                cursor = yesterday
            }
            var streak = 0
            while written.contains(cursor), let before = DayKey.adding(-1, to: cursor, in: timeZone) {
                streak += 1
                cursor = before
            }
            return streak
        }

        /// The hour (0-23) the period's entries were usually written, by `JournalHabits`' rule.
        public var usualHour: Int? {
            JournalHabits.typicalHour(of: inRange.map(\.createdAt), in: timeZone)
        }

        /// Over all time, not the period.
        public var nightsWritten: Int { Set(all.map(\.dayKey)).count }

        public var isUnlocked: Bool { nightsWritten >= Self.unlockNights }
    }

    public enum Year {
        /// Entries per month of `year`, January first.
        public static func monthCounts(of days: [JournalEntryDay], year: Int) -> [Int] {
            var counts = Array(repeating: 0, count: 12)
            for key in Set(days.map(\.dayKey)) {
                guard let month = MonthKey(dayKey: key), month.year == year else { continue }
                counts[month.month - 1] += 1
            }
            return counts
        }

        /// The shade of a month circle: 0 none, 1 for 1 to 9 entries, 2 for 10 to 21, 3 for 22 or more.
        public static func level(for count: Int) -> Int {
            switch count {
            case ..<1: 0
            case 1..<10: 1
            case 10..<22: 2
            default: 3
            }
        }

        /// 0 for no words. Otherwise 1 to 3 by thirds of the written days' words, the longest third
        /// darkest and a tie with the cutoff going to the darker shade. A third of the days rounds
        /// down but never below one, so any writing at all has a darkest day.
        public static func level(forWords words: Int, among written: [Int]) -> Int {
            guard words > 0 else { return 0 }
            guard !written.isEmpty else { return 1 }
            let descending = written.sorted(by: >)
            func cutoff(_ share: Int) -> Int { descending[max(1, written.count * share / 3) - 1] }
            if words >= cutoff(1) { return 3 }
            return words >= cutoff(2) ? 2 : 1
        }
    }
}
