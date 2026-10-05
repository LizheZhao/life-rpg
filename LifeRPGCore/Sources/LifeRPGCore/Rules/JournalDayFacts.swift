import Foundation
import SwiftData

/// What the reading page says about the day around a journal, none of which is stored in turns:
/// how much was done and what kind of day it was. Read from the day's rows, never cached, so it
/// can not disagree with the Today page or the calendar.
public struct JournalDayFacts: Equatable, Sendable {
    /// Quests and routines completed that day, counted the way the journal's own signals count them.
    public let completed: Int
    /// "low day" and the like, from the day's `DailyContext`, worded by `Tier.dayText` as the Today
    /// page is. Nil when the day has no context (a day before the app generated one).
    public let tierText: String?

    public static func of(dayKey: String, quests: [DailyQuest], occurrences: [RoutineOccurrence],
                          context: DailyContext?) -> JournalDayFacts {
        let signals = JournalSignals(dayKey: dayKey, quests: quests, occurrences: occurrences,
                                     context: context, ratings: [])
        return JournalDayFacts(completed: signals.completedCount, tierText: context?.tier.dayText)
    }

    /// The facts of `dayKey` from the store: the day's quests, the occurrences, and its context.
    public static func read(dayKey: String, in context: ModelContext) throws -> JournalDayFacts {
        of(dayKey: dayKey,
           quests: try DayService.quests(on: dayKey, in: context),
           occurrences: try context.fetch(FetchDescriptor<RoutineOccurrence>()),
           context: try DayService.dailyContext(for: dayKey, in: context))
    }
}
