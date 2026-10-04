import Foundation

/// The text of a day's journal as it goes to Apple Journal.
///
/// It is the user's own writing under the questions that prompted it, in order, and nothing else:
/// no summary, no rewording, no model text beyond the question lines the user was shown. A
/// skipped or misfit turn has nothing to say and is left out, as is the safety line, which was
/// never the user's.
public enum JournalComposer {
    public static func title(dayKey: String, language: JournalLanguage) -> String {
        language == .zhHans ? "日记 \(dayKey)" : "Journal \(dayKey)"
    }

    /// Empty when no turn has an answer, so the caller has nothing to offer to save.
    public static func text(turns: [JournalTurn], language: JournalLanguage) -> String {
        let written = turns
            .sorted { ($0.dayKey, $0.index) < ($1.dayKey, $1.index) }
            .filter { $0.outcome == .answered && $0.kind != .safety
                && !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let first = written.first else { return "" }

        var blocks = [title(dayKey: first.dayKey, language: language)]
        for turn in written {
            // Free writing has no question above it.
            blocks.append(turn.questionText.isEmpty ? turn.answer : turn.questionText + "\n" + turn.answer)
        }
        return blocks.joined(separator: "\n\n")
    }
}
