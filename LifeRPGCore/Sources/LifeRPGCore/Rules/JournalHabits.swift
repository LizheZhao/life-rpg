import Foundation

/// What the journal has learned about how the user writes, derived on demand from past turns.
///
/// Nothing here is stored: a cached habit would go stale the moment a turn is added and could not
/// be corrected by editing history. Only turns from before `dayKey`, within `windowDays`, are read,
/// so the habits are the same all day however many turns are recorded, which is what keeps the
/// planner's ranking stable while a day's journal is in progress.
public struct JournalHabits: Equatable, Sendable {
    /// How far back habits are read. A routine of two months ago still describes the user; last
    /// year's does not.
    public static let windowDays = 60
    /// Typical hour needs at least this many turns to mean anything.
    public static let minimumTurnsForHour = 5
    /// No kind is ever weighted below this, so a run of skipped questions quietens a kind
    /// without making it disappear.
    public static let weightFloor = 0.25
    /// How far back question texts are kept to avoid repeating: two weeks reads as a fresh
    /// question, a month back is forgotten.
    public static let recentQuestionDays = 14

    /// Median length, in characters, of the answers that say something. Nil with none.
    public let medianAnswerLength: Int?
    /// The usual hour (0-23) the user responds, counted from the day boundary so a night owl's
    /// 23:00 and 01:00 average to midnight. Nil with fewer than `minimumTurnsForHour` turns.
    public let typicalHour: Int?
    public let usesEmoji: Bool
    /// Smoothed answered-rate per kind that has history; `weight(for:)` fills in the rest.
    public let weights: [JournalPromptKind: Double]
    /// Pool row id to the dayKey it was last asked on. A model-worded turn counts for the row it
    /// was worded from (its `promptID` is the fallback row), so the fallback and the anchors keep
    /// rotating whoever wrote the text shown.
    public let lastUsedDay: [String: String]
    /// What was asked in the last `recentQuestionDays` days, newest first, blanks left out. Model
    /// wording is included: the point is that nothing repeats, whoever wrote it.
    public let recentQuestionTexts: [String]

    public init(medianAnswerLength: Int?, typicalHour: Int?, usesEmoji: Bool,
                weights: [JournalPromptKind: Double],
                lastUsedDay: [String: String] = [:], recentQuestionTexts: [String] = []) {
        self.medianAnswerLength = medianAnswerLength
        self.typicalHour = typicalHour
        self.usesEmoji = usesEmoji
        self.weights = weights
        self.lastUsedDay = lastUsedDay
        self.recentQuestionTexts = recentQuestionTexts
    }

    public static let none = JournalHabits(medianAnswerLength: nil, typicalHour: nil, usesEmoji: false, weights: [:])

    /// 1.0 for a kind with no history: ranking is by base score alone until there is something to learn.
    public func weight(for kind: JournalPromptKind) -> Double { weights[kind] ?? 1.0 }

    public static func derive(from turns: [JournalTurn], asOf dayKey: String,
                              timeZone: TimeZone = .current) -> JournalHabits {
        let since = DayKey.adding(-windowDays, to: dayKey, in: timeZone) ?? dayKey
        let history = turns.filter { $0.dayKey < dayKey && $0.dayKey >= since && $0.kind != .safety
            && !$0.isBlankFreeWriting }
        guard !history.isEmpty else { return .none }

        let lengths = history.filter { $0.outcome == .answered }
            .map { $0.answer.trimmingCharacters(in: .whitespacesAndNewlines).count }
            .filter { $0 > 0 }
            .sorted()
        let median = lengths.isEmpty ? nil : (lengths[(lengths.count - 1) / 2] + lengths[lengths.count / 2]) / 2

        var hour: Int?
        if history.count >= minimumTurnsForHour {
            let calendar = LifeCalendar.gregorian(timeZone)
            let start = LifeCalendar.dayStartHour
            let shifted = history.map { (calendar.component(.hour, from: $0.answeredAt) - start + 24) % 24 }.sorted()
            hour = (shifted[(shifted.count - 1) / 2] + start) % 24
        }

        var weights: [JournalPromptKind: Double] = [:]
        for (kind, rows) in Dictionary(grouping: history, by: \.kind) {
            let answered = rows.filter { $0.outcome == .answered }.count
            let skipped = rows.filter { $0.outcome == .skipped }.count
            let misfit = rows.filter { $0.outcome == .misfit }.count
            // Add-one smoothing on the answered side: no history reads 1, and each skip counts once
            // against while a misfit, which says the question itself was wrong, counts twice.
            weights[kind] = max(weightFloor, Double(answered + 1) / Double(answered + skipped + 2 * misfit + 1))
        }

        var lastUsed: [String: String] = [:]
        for turn in history where !turn.promptID.isEmpty {
            lastUsed[turn.promptID] = max(lastUsed[turn.promptID] ?? "", turn.dayKey)
        }
        let recentSince = DayKey.adding(-recentQuestionDays, to: dayKey, in: timeZone) ?? dayKey
        let recent = history
            .filter { $0.dayKey >= recentSince && !$0.questionText.isEmpty }
            .sorted { ($0.dayKey, $0.index) > ($1.dayKey, $1.index) }
            .map(\.questionText)

        return JournalHabits(medianAnswerLength: median, typicalHour: hour,
                             usesEmoji: history.contains { $0.answer.contains(where: Self.isEmoji) },
                             weights: weights, lastUsedDay: lastUsed, recentQuestionTexts: recent)
    }

    private static func isEmoji(_ character: Character) -> Bool {
        character.unicodeScalars.contains { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value >= 0x203C) }
    }

    /// One short instruction for the model prompt: how long a question the user's answers suggest
    /// they will meet, and in what register.
    public func styleHint(language: JournalLanguage) -> String {
        enum Length { case short, medium, long }
        let length: Length = switch medianAnswerLength {
        case .some(..<30): .short
        case .some(120...): .long
        default: .medium
        }
        switch language {
        case .en:
            let size = switch length {
            case .short: "The user writes short answers. Keep the question under 12 words."
            case .medium: "Keep the question under 20 words."
            case .long: "The user writes at length. A question of up to 25 words is fine."
            }
            return size + (usesEmoji ? " Use a light, casual register." : " Use a plain, calm register.")
        case .zhHans:
            let size = switch length {
            case .short: "用户的回答很短。问题控制在 20 个字以内。"
            case .medium: "问题控制在 30 个字以内。"
            case .long: "用户习惯写得较长。问题可以长到 40 个字。"
            }
            return size + (usesEmoji ? "语气轻松随意。" : "语气平静朴素。")
        }
    }
}
