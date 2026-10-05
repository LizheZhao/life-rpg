import Foundation

/// The whole Trends page as one value: every number, label and ordering the view draws, so the view
/// only lays rows out. Built from the rows the page's queries hold, nothing is stored.
public struct TrendsPage: Equatable, Sendable {
    public let period: JournalTrends.Period
    /// "September · 24 entries", the week's date range, or the year, each with the entry count.
    /// Until the page unlocks it is "unlocks after 7 nights".
    public let subtitle: String
    /// A day inside the period before this one, nil when nothing was written earlier than the
    /// period, so the control never leads to an empty page.
    public let previousAnchor: String?
    /// A day inside the period after this one, nil when the period holds today.
    public let nextAnchor: String?
    public let content: Content

    public enum Content: Equatable, Sendable {
        case locked(Locked)
        case unlocked(Unlocked)
    }

    /// Fewer than `unlockNights` nights written, over all time.
    public struct Locked: Equatable, Sendable {
        public let progress: JournalTrends.Locked.Progress
        public let explanation: String
        public let previews: [JournalTrends.Locked.Preview]
    }

    public struct Unlocked: Equatable, Sendable {
        public let totalWords: Int
        /// All-time, as of today: a period filter would get it wrong.
        public let streak: Int
        /// The hour the period's entries were usually written, in the locale's own form ("11 PM").
        public let usualHour: String?
        /// Nil when nothing was written in the period.
        public let wordsPerDay: WordsPerDay?
        public let about: About?
        public let calendar: [CalendarCell]
        public let favorites: Favorites?
        public let energy: Energy?
        public let gratitude: [JournalTrends.Gratitude.Phrase]
        public let year: [MonthCircle]
    }

    public struct WordsPerDay: Equatable, Sendable {
        public struct Bar: Equatable, Sendable {
            public let dayKey: String
            public let words: Int
            /// 0 to 1 against the longest day of the period.
            public let fraction: Double
            /// 0 for a quiet day, 1 to 3 by thirds of the written days, 3 the longest.
            public let level: Int
        }

        public let average: Int
        public let bars: [Bar]
        /// First, middle and last day of the period, as dates ("Sep 1").
        public let axis: [String]
    }

    public struct About: Equatable, Sendable {
        public struct Row: Equatable, Sendable {
            public let word: String
            public let count: Int
            /// 0 to 1 against the commonest word of the list.
            public let fraction: Double
        }

        public let title: String
        public let subtitle: String
        public let rows: [Row]
    }

    public struct CalendarCell: Equatable, Sendable {
        public let dayKey: String
        public let level: Int
    }

    public struct Favorites: Equatable, Sendable {
        public struct Row: Equatable, Sendable {
            public let text: String
            /// "22 times · light version 9"
            public let detail: String
            /// 1 to 5, nil when unrated.
            public let stars: Int?
        }

        public let subtitle: String
        public let rows: [Row]
    }

    public struct Energy: Equatable, Sendable {
        public struct Bar: Equatable, Sendable {
            public let dayKey: String
            /// 0 to 1 against the busiest day shown.
            public let fraction: Double
            public let isLow: Bool
        }

        public let bars: [Bar]
        /// Percent of a normal day's work a low day gets done, nil without enough days to say.
        public let lowDayPercent: Int?
    }

    public struct MonthCircle: Equatable, Sendable {
        public let label: String
        public let entries: Int
        /// 0 none, 1 to 3 darker with more entries.
        public let level: Int
    }
}

extension TrendsPage {
    /// `anchor` is any day of the period to show; the page opens on `today`. `days` is the whole
    /// history (`JournalHistory.days`): the period is cut here, and the other periods are what the
    /// word list is compared against.
    public static func build(period: JournalTrends.Period, anchor: String, today: String,
                             days: [JournalDay], quests: [DailyQuest], occurrences: [RoutineOccurrence],
                             ratings: [QuestRating], contexts: [DailyContext], language: JournalLanguage,
                             timeZone: TimeZone = .current, locale: Locale = .current) -> TrendsPage {
        let range = JournalTrends.range(of: period, containing: anchor, in: timeZone)
            ?? JournalTrends.range(of: period, containing: today, in: timeZone)
            ?? JournalTrends.DayRange(first: today, last: today)
        let writing = JournalTrends.Writing(days: days, range: range, timeZone: timeZone)
        let formatter = Formatter(timeZone: timeZone, locale: locale)

        let previous = days.contains { $0.dayKey < range.first }
            ? DayKey.adding(-1, to: range.first, in: timeZone) : nil
        let next = range.contains(today) || range.last > today ? nil : DayKey.adding(1, to: range.last, in: timeZone)

        guard writing.isUnlocked else {
            let locked = Locked(progress: JournalTrends.Locked.progress(nightsWritten: writing.nightsWritten),
                                explanation: JournalTrends.Locked.explanation,
                                previews: JournalTrends.Locked.previews)
            return TrendsPage(period: period,
                              subtitle: "unlocks after \(JournalTrends.Writing.unlockNights) nights",
                              previousAnchor: nil, nextAnchor: nil, content: .locked(locked))
        }

        let entries = writing.entries
        let noun = period.noun
        let periodDays = days.filter { range.contains($0.dayKey) }
        let byDay = writing.wordsByDay

        let wordsPerDay: WordsPerDay? = {
            guard entries > 0 else { return nil }
            let longest = max(1, byDay.map(\.words).max() ?? 1)
            let bars = byDay.map {
                WordsPerDay.Bar(dayKey: $0.dayKey, words: $0.words, fraction: Double($0.words) / Double(longest),
                                level: $0.level)
            }
            let keys = byDay.map(\.dayKey)
            let axis = [keys.first, keys.isEmpty ? nil : keys[(keys.count - 1) / 2], keys.last]
                .compactMap { $0.map(formatter.shortDate) }
            return WordsPerDay(average: writing.averageWords, bars: bars, axis: axis)
        }()

        let about: About? = {
            let others = days.filter { !range.contains($0.dayKey) }
            let words = JournalTrends.Words.distinctive(period: periodDays, others: others, language: language)
            // The list is ranked by how much a word stands out, so its first row need not be the commonest.
            guard let top = words.map(\.count).max() else { return nil }
            return About(title: "What this \(noun) was about",
                         subtitle: "Words that stood out versus your other \(noun)s",
                         rows: words.map { About.Row(word: $0.word, count: $0.count,
                                                     fraction: Double($0.count) / Double(top)) })
        }()

        let favorites: Favorites? = {
            let found = JournalTrends.Quests.favorites(quests: quests, occurrences: occurrences,
                                                       ratings: ratings, in: range)
            guard !found.isEmpty else { return nil }
            return Favorites(subtitle: "Done most and rated best this \(noun)",
                             rows: found.map {
                                 Favorites.Row(text: $0.text, detail: detail(of: $0), stars: $0.stars)
                             })
        }()

        let energy: Energy? = {
            let energyDays = JournalTrends.Energy.days(in: range, quests: quests, occurrences: occurrences,
                                                       contexts: contexts)
            guard energyDays.contains(where: \.isLow) else { return nil }
            let busiest = max(1, energyDays.map(\.done).max() ?? 1)
            return Energy(bars: energyDays.map {
                              Energy.Bar(dayKey: $0.dayKey, fraction: Double($0.done) / Double(busiest),
                                         isLow: $0.isLow)
                          },
                          lowDayPercent: JournalTrends.Energy.lowDayRatio(energyDays))
        }()

        let year = MonthKey(dayKey: range.first)?.year ?? 0
        let counts = JournalTrends.Year.monthCounts(of: days, year: year)
        let circles = counts.allSatisfy({ $0 == 0 }) ? [] : counts.enumerated().map { index, count in
            MonthCircle(label: formatter.monthName(index), entries: count, level: JournalTrends.Year.level(for: count))
        }

        let unlocked = Unlocked(
            totalWords: writing.totalWords,
            streak: writing.writingStreak(asOf: today),
            usualHour: writing.usualHour.map(formatter.hour),
            wordsPerDay: wordsPerDay,
            about: about,
            calendar: entries == 0 ? [] : byDay.map { CalendarCell(dayKey: $0.dayKey, level: $0.level) },
            favorites: favorites,
            energy: energy,
            gratitude: JournalTrends.Gratitude.phrases(in: periodDays),
            year: circles)
        return TrendsPage(period: period,
                          subtitle: "\(formatter.label(of: range, period: period)) \u{00B7} \(entries) \(entries == 1 ? "entry" : "entries")",
                          previousAnchor: previous, nextAnchor: next, content: .unlocked(unlocked))
    }

    private static func detail(of favorite: JournalTrends.Quests.Favorite) -> String {
        var text = "\(favorite.times) \(favorite.times == 1 ? "time" : "times")"
        if favorite.lightCount > 0 { text += " \u{00B7} light version \(favorite.lightCount)" }
        return text
    }

    /// Dates and the hour in the user's locale.
    private struct Formatter {
        let timeZone: TimeZone
        let locale: Locale

        private func formatter(_ template: String) -> DateFormatter {
            let f = DateFormatter()
            f.locale = locale
            f.timeZone = timeZone
            f.setLocalizedDateFormatFromTemplate(template)
            return f
        }

        func shortDate(_ dayKey: String) -> String {
            DayKey.date(dayKey, in: timeZone).map(formatter("MMMd").string(from:)) ?? dayKey
        }

        func label(of range: JournalTrends.DayRange, period: JournalTrends.Period) -> String {
            switch period {
            case .week: return "\(shortDate(range.first)) \u{2013} \(shortDate(range.last))"
            case .month: return DayKey.date(range.first, in: timeZone).map(formatter("MMMM").string(from:)) ?? range.first
            case .year: return String(range.first.prefix(4))
            }
        }

        func hour(_ hour: Int) -> String {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date(timeIntervalSince1970: 0)) ?? Date()
            return formatter("j").string(from: date)
        }

        func monthName(_ index: Int) -> String {
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = locale
            return calendar.shortStandaloneMonthSymbols[index]
        }
    }
}

extension JournalTrends.Period {
    /// "week", "month" or "year": how the page's titles name the period.
    public var noun: String {
        switch self {
        case .week: "week"
        case .month: "month"
        case .year: "year"
        }
    }
}
