import Foundation

extension JournalTrends {
    /// A random quest that was done and not swapped for something else.
    static func isDone(_ quest: DailyQuest) -> Bool { quest.points != nil && !quest.replaced }

    /// A routine occurrence that was done (not skipped) and not swapped by hand for an ad-hoc one.
    static func isDone(_ occurrence: RoutineOccurrence) -> Bool {
        occurrence.completedDayKey != nil && !occurrence.skipped && !occurrence.isReplaced
    }

    /// "Favorite quests": what was done most, and how it was rated, over one period.
    public enum Quests {
        public struct Favorite: Equatable, Sendable {
            /// The snapshot wording of the newest completion, the original routine text rather than
            /// its light version's.
            public let text: String
            public let times: Int
            /// How many of `times` were done as a downgrade version.
            public let lightCount: Int
            /// 1 to 5, the period's mean rating (-2 to 2) shifted up by three; nil when unrated, which
            /// the page draws as empty stars.
            public let stars: Int?
        }

        /// What counts as one thing: a routine by its id (a light version is still that routine,
        /// as is a library ad-hoc pick of it), a random quest by its template, and anything without
        /// an id by its text.
        private enum Thing: Hashable {
            case id(UUID)
            case text(String)
        }

        private struct Completion {
            let thing: Thing
            let text: String
            let dayKey: String
            let isLight: Bool
        }

        /// Ranked by times done, then mean rating (unrated last), then text. Ratings count when
        /// they were filed inside `range`, whichever day the completion was.
        public static func favorites(quests: [DailyQuest], occurrences: [RoutineOccurrence],
                                     ratings: [QuestRating], in range: DayRange, limit: Int = 3) -> [Favorite] {
            guard limit > 0 else { return [] }
            let fromQuests = quests.filter { isDone($0) && range.contains($0.dayKey) }.map {
                Completion(thing: $0.templateID.map(Thing.id) ?? .text($0.textSnapshot),
                           text: $0.textSnapshot, dayKey: $0.dayKey, isLight: false)
            }
            let fromRoutines = occurrences.filter { isDone($0) && range.contains($0.completedDayKey ?? "") }.map {
                Completion(thing: ($0.routineID ?? $0.adHocSourceRoutineID).map(Thing.id) ?? .text($0.textSnapshot),
                           text: $0.textSnapshot, dayKey: $0.completedDayKey ?? "",
                           isLight: $0.usedDegraded && $0.degradedRoutineID != nil)
            }

            var scores: [UUID: [Int]] = [:]
            for rating in ratings where range.contains(rating.dayKey) {
                if let id = rating.targetID { scores[id, default: []].append(rating.rating) }
            }

            struct Row {
                let favorite: Favorite
                let mean: Double
            }
            let rows = Dictionary(grouping: fromQuests + fromRoutines, by: \.thing).map { thing, group -> Row in
                var mean: Double?
                if case .id(let id) = thing, let given = scores[id], !given.isEmpty {
                    mean = Double(given.reduce(0, +)) / Double(given.count)
                }
                let newest = group.max { ($0.dayKey, $1.text) < ($1.dayKey, $0.text) }!
                return Row(favorite: Favorite(text: newest.text, times: group.count,
                                              lightCount: group.filter(\.isLight).count,
                                              stars: mean.map { min(5, max(1, Int(($0 + 3).rounded()))) }),
                           mean: mean ?? -.infinity)
            }
            return rows
                .sorted { ($1.favorite.times, $1.mean, $0.favorite.text) < ($0.favorite.times, $0.mean, $1.favorite.text) }
                .prefix(limit)
                .map(\.favorite)
        }
    }

    /// "Low energy days": per day the points earned against the tier the day was set to. Points
    /// rather than a count, so one big quest is not the same as one small one.
    public enum Energy {
        public struct Day: Equatable, Sendable {
            public let dayKey: String
            /// What the day's finished quests and routines paid, by the day they were finished.
            public let points: Int
            public let isLow: Bool
        }

        /// A low day needs this many of each kind before a comparison says anything.
        static let minimumDays = 3

        /// The days of `range` the app generated (one `DailyContext` each), in order. A day the app
        /// never opened has no tier to compare, so it is not a bar.
        public static func days(in range: DayRange, quests: [DailyQuest], occurrences: [RoutineOccurrence],
                                contexts: [DailyContext]) -> [Day] {
            var earned: [String: Int] = [:]
            for quest in quests where isDone(quest) { earned[quest.dayKey, default: 0] += quest.points ?? 0 }
            for occurrence in occurrences where isDone(occurrence) {
                earned[occurrence.completedDayKey ?? "", default: 0] += occurrence.awardedPoints ?? 0
            }
            return contexts.filter { range.contains($0.dayKey) }
                .sorted { $0.dayKey < $1.dayKey }
                .map { Day(dayKey: $0.dayKey, points: earned[$0.dayKey] ?? 0, isLow: $0.tier.isLow) }
        }

        /// What percent of a normal day's points a low day earns, rounded: the mean points on low
        /// days over the mean on the others. Nil with fewer than three days of either kind, or when
        /// the other days earned nothing to compare against.
        public static func lowDayRatio(_ days: [Day]) -> Int? {
            let low = days.filter(\.isLow)
            let other = days.filter { !$0.isLow }
            let otherPoints = other.reduce(0) { $0 + $1.points }
            guard low.count >= minimumDays, other.count >= minimumDays, otherPoints > 0 else { return nil }
            let lowPoints = low.reduce(0) { $0 + $1.points }
            // (lowPoints / low.count) / (otherPoints / other.count) as one division of integers.
            return Int((100 * Double(lowPoints * other.count) / Double(otherPoints * low.count)).rounded())
        }
    }
}
