import Foundation
@testable import LifeRPGCore

/// `JournalDay`s for the Trends rules, made the way the app makes them: from turns.
enum TrendsFixtures {
    typealias F = JournalFixtures

    /// One free-writing day of exactly `words` words, written at `hour` (Tokyo).
    static func day(_ dayKey: String, words: Int, hour: Int = 22) -> JournalDay {
        days([(dayKey, words)], hour: hour)[0]
    }

    /// Newest first, as `JournalHistory.days` returns them.
    static func days(_ spec: [(String, Int)], hour: Int = 22) -> [JournalDay] {
        let turns = spec.map { F.freeWriting(String(repeating: "word ", count: $0.1), on: $0.0, hour: hour) }
        return JournalHistory.days(from: turns, language: .en)
    }

    /// Days whose text is given, one free-writing turn each.
    static func days(texts: [(String, String)], hour: Int = 22) -> [JournalDay] {
        JournalHistory.days(from: texts.map { F.freeWriting($0.1, on: $0.0, hour: hour) }, language: .en)
    }
}
