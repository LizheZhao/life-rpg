import Foundation
@testable import LifeRPGCore

/// Days for the Trends rules: the one-document-per-day `JournalEntryDay`s every Trends rule reads.
enum TrendsFixtures {
    typealias F = JournalFixtures

    /// A day made of the given blocks, started and last saved at `hour:minute`.
    static func day(_ dayKey: String, _ blocks: [JournalBlock], hour: Int = 22, minute: Int = 0) -> JournalEntryDay {
        let started = Fixtures.date(dayKey, hour: hour).addingTimeInterval(TimeInterval(minute * 60))
        return JournalEntryDay(dayKey: dayKey, document: JournalDocument(blocks: blocks), isDone: false,
                               writtenAt: started, createdAt: started)
    }

    /// A day with one free-text block.
    static func day(_ dayKey: String, text: String, hour: Int = 22, minute: Int = 0) -> JournalEntryDay {
        day(dayKey, [EntryFixtures.text(1, text)], hour: hour, minute: minute)
    }

    /// Newest first, as `JournalEntryHistory.days` returns them: a day of `count` words each.
    static func entryDays(_ spec: [(String, Int)], hour: Int = 22) -> [JournalEntryDay] {
        newestFirst(spec.map { day($0.0, text: String(repeating: "word ", count: $0.1), hour: hour) })
    }

    /// Days whose text is given, one free-text block each.
    static func entryDays(texts: [(String, String)], hour: Int = 22) -> [JournalEntryDay] {
        newestFirst(texts.map { day($0.0, text: $0.1, hour: hour) })
    }

    private static func newestFirst(_ days: [JournalEntryDay]) -> [JournalEntryDay] {
        days.sorted { $0.dayKey > $1.dayKey }
    }
}
