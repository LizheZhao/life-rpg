#if targetEnvironment(simulator)
import Foundation
import LifeRPGCore
import SwiftData

/// Turn-based journal days as the build before entries wrote them, so the launch migration can be
/// watched on a store that never had them. Simulator only, run from Debug. Writes `JournalTurn`
/// rows directly (the writer that made them is gone); none of it came from using the app.
enum JournalTurnSeed {
    /// Three days before `today`: a guided day with an unanswered question, a free-writing day, and
    /// a guided day left open (no closing turn). Returns the day keys written.
    @MainActor
    static func seed(endingBefore today: String, in context: ModelContext) throws -> [String] {
        let days = [2, 3, 4].compactMap { DayKey.adding(-$0, to: today) }
        guard days.count == 3 else { return [] }
        let existing = Set(try context.fetch(FetchDescriptor<JournalTurn>()).map(\.dayKey))
        var written: [String] = []

        func turn(_ day: String, _ index: Int, _ kind: JournalPromptKind, question: String, answer: String,
                  outcome: JournalOutcome = .answered, source: JournalSource = .template) {
            let row = JournalTurn()
            row.dayKey = day
            row.index = index
            row.kind = kind
            row.promptID = question.isEmpty ? "" : "debug.\(kind.rawValue)"
            row.questionText = question
            row.answer = answer
            row.outcome = outcome
            row.source = source
            let at = (DayKey.date(day) ?? Date()).addingTimeInterval(Double(20 * 3600 + index * 300))
            row.askedAt = at
            row.answeredAt = at.addingTimeInterval(120)
            context.insert(row)
        }

        if !existing.contains(days[0]) {
            turn(days[0], 0, .opening, question: "How was today, in a word?", answer: "Heavy, but I got through it.")
            turn(days[0], 1, .good, question: "What was good about the walk?", answer: "The first ten minutes were the hard part.",
                 source: .model)
            turn(days[0], 2, .skip, question: "Why did the stretching get skipped?", answer: "", outcome: .skipped)
            turn(days[0], 3, .closing, question: "Anything else before you sleep?", answer: "Tomorrow I will start earlier.")
            written.append(days[0])
        }
        if !existing.contains(days[1]) {
            turn(days[1], 0, .closing, question: "", answer: "Free writing from three days back. The river was calm and I took the long way home.")
            written.append(days[1])
        }
        if !existing.contains(days[2]) {
            turn(days[2], 0, .opening, question: "How was today, in a word?", answer: "Quiet.")
            turn(days[2], 1, .good, question: "What was good today?", answer: "Reading before bed.")
            written.append(days[2])
        }
        try context.save()
        return written
    }
}
#endif
