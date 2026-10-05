import Foundation

/// A short phrase for the free-writing page to start a sentence with, which the user finishes.
public struct JournalStarter: Equatable, Sendable {
    public let id: String
    /// The phrase in the language it was picked for.
    public let text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }

    /// `text` and one space after it, as a new paragraph: right onto an empty page, after a blank
    /// line onto anything already written (its trailing whitespace trimmed so the gap is exactly
    /// one blank line).
    public func insert(into page: String) -> String {
        var written = page
        while let last = written.last, last.isWhitespace { written.removeLast() }
        return (written.isEmpty ? "" : written + "\n\n") + text + " "
    }
}

/// Which starters to offer above the keyboard of the free-writing page.
///
/// "Grateful for" is always first: the Trends page counts what follows it. The rest are picked by
/// the day, ranked as the planner ranks the kinds it asks about (base score times the habit weight
/// of the kind), alongside two fillers that fit any day. A filler's base score is 1, the lowest, so
/// it comes after the day's starters unless the habit weights pull one of those under it. A tie
/// goes to the starter used least recently, which is read from the turns
/// (`JournalHabits.starterLastUsedDay`) so the same phrase does not come every night, and then to
/// table order; the fillers take turns by the day's hash, as the planner's pool rows do.
public enum JournalStarters {
    struct Row {
        let id: String
        let kind: JournalPromptKind
        let en: String
        let zh: String
        /// Nil when the day does not call for it. No score at all is the pinned first row.
        let score: ((JournalSignals) -> Double?)?
        var isFiller = false

        func text(in language: JournalLanguage) -> String { language == .zhHans ? zh : en }
    }

    static let grateful = Row(id: "starter.grateful", kind: .good, en: "Grateful for", zh: "今天感恩的是", score: nil)

    /// The whole table, in the order a tie falls back to.
    static let table: [Row] = [
        grateful,
        Row(id: "starter.obstacle", kind: .skip, en: "What got in the way was", zh: "拦住我的是",
            score: { $0.skipped.isEmpty ? nil : 3 }),
        Row(id: "starter.lowEnergy", kind: .heavy, en: "Low energy felt like", zh: "没力气的感觉像是",
            score: { $0.tier.isLow ? 4 : nil }),
        Row(id: "starter.heaviest", kind: .heavy, en: "The heaviest part was", zh: "最沉重的部分是",
            score: { ($0.averageRating ?? 0) <= -1 ? 4 : nil }),
        Row(id: "starter.favorite", kind: .good, en: "Favorite moment was", zh: "最喜欢的瞬间是",
            score: { signals in
                signals.completed.compactMap(\.rating).max().flatMap { $0 >= 1 ? 2 + 0.5 * Double($0 - 1) : nil }
            }),
        Row(id: "starter.eye", kind: .choice, en: "What caught my eye was", zh: "吸引我目光的是",
            score: { $0.choiceItem == nil ? nil : 2 }),
        Row(id: "starter.tomorrow", kind: .closing, en: "Tomorrow I want to", zh: "明天我想",
            score: { _ in 1 }, isFiller: true),
        Row(id: "starter.thinking", kind: .opening, en: "I keep thinking about", zh: "我一直在想",
            score: { _ in 1 }, isFiller: true),
    ]

    /// At most `limit` starters, "Grateful for" first (it survives any limit above 0), then the
    /// day's best.
    public static func starters(signals: JournalSignals, habits: JournalHabits, language: JournalLanguage,
                                limit: Int = 4) -> [JournalStarter] {
        guard limit > 0 else { return [] }
        let fillers = table.filter(\.isFiller)
        let offset = Int(JournalPlanner.stableHash(signals.dayKey) % UInt64(fillers.count))

        struct Ranked {
            let row: Row
            let rank: Double
            let lastUsed: String
            let tie: Int
        }
        let ranked: [Ranked] = table.enumerated().compactMap { index, row in
            guard let score = row.score, let value = score(signals) else { return nil }
            let tie = fillers.firstIndex { $0.id == row.id }
                .map { 1000 + ($0 - offset + fillers.count) % fillers.count } ?? index
            return Ranked(row: row, rank: value * habits.weight(for: row.kind),
                          lastUsed: habits.starterLastUsedDay[row.id] ?? "", tie: tie)
        }
        .sorted { ($1.rank, $0.lastUsed, $0.tie) < ($0.rank, $1.lastUsed, $1.tie) }

        return ([grateful] + ranked.map(\.row)).prefix(limit).map {
            JournalStarter(id: $0.id, text: $0.text(in: language))
        }
    }

    /// The paragraph without the starter it begins with: the starter is the app's text, not the
    /// user's words, so anything that reads the writing for its content leaves it out.
    static func strippingStarter(from paragraph: String) -> String {
        for row in table {
            for text in [row.en, row.zh] where paragraph.hasPrefix(text) { return String(paragraph.dropFirst(text.count)) }
        }
        return paragraph
    }

    /// The starter a paragraph of the user's writing begins with, in either language.
    static func starter(beginning paragraph: String) -> String? {
        table.first { paragraph.hasPrefix($0.en) || paragraph.hasPrefix($0.zh) }?.id
    }
}
