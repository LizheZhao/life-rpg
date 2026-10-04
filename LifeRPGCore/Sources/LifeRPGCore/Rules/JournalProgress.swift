import Foundation

/// Where a day's journal stands, for the one line on the Today page. Read from the day's turns
/// alone, like the planner, so it can not disagree with what the journal would ask next.
public enum JournalProgress: Equatable, Sendable {
    case notStarted
    /// `answered` counts the turns that will appear in the composed text.
    case inProgress(answered: Int)
    case done(answered: Int)

    public static func of(_ turns: [JournalTurn]) -> JournalProgress {
        guard !turns.isEmpty else { return .notStarted }
        let answered = JournalComposer.written(turns).count
        return isClosed(turns) ? .done(answered: answered) : .inProgress(answered: answered)
    }

    /// The closing turn, whether it answers the closing question or is free writing, ends the day.
    public static func isClosed(_ turns: [JournalTurn]) -> Bool {
        turns.contains { $0.kind == .closing }
    }
}
