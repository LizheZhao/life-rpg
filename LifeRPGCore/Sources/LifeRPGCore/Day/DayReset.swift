import Foundation
import SwiftData

/// Reopening a day that was already played.
///
/// **This is a debug tool and nothing on the today page reaches it.** `PLAN.md` §3 makes completion
/// final on purpose — a reversible tick turns the points roll into something you can re-roll until
/// the number is good, and the whole economy rests on that not being possible. This exists so the
/// reveal animation and the scoring rules can be exercised more than once a day while they are
/// being built, and it lives behind the debug page for the same reason the raw store export lives
/// behind the startup error screen.
///
/// It is a genuine undo, not a partial one: the ledger entries that paid for those quests are
/// deleted, so the balance goes back to what it was rather than keeping points for work that is
/// now marked undone.
public enum DayReset {
    public struct Result: Equatable, Sendable {
        public var questsReopened: Int
        public var hiddenRemoved: Int
        public var ledgerEntriesDeleted: Int

        public var description: String {
            "Reopened \(questsReopened) quest(s), removed \(hiddenRemoved) hidden, "
            + "deleted \(ledgerEntriesDeleted) ledger entr(ies)"
        }
    }

    @discardableResult
    public static func reopen(_ context: ModelContext, dayKey: String) throws -> Result {
        var result = Result(questsReopened: 0, hiddenRemoved: 0, ledgerEntriesDeleted: 0)
        let quests = try DayService.quests(on: dayKey, in: context)
        let questIDs = Set(quests.map(\.id))

        for entry in try context.fetch(FetchDescriptor<LedgerEntry>())
        where entry.refID.map(questIDs.contains) == true {
            context.delete(entry)
            result.ledgerEntriesDeleted += 1
        }

        for quest in quests {
            // The completion stamp on the template came from this very day, so clearing it puts
            // the cooldown back where it was. Read before the row is deleted below.
            for template in try Completion.templates(of: quest, in: context)
            where template.lastCompletedDayKey == dayKey {
                template.lastCompletedDayKey = nil
            }

            if quest.isHiddenSlot {
                // The hidden slot is drawn at most once a day, keyed on the row existing at all —
                // so reopening it means removing the row, not clearing its fields.
                context.delete(quest)
                result.hiddenRemoved += 1
                continue
            }

            quest.points = nil
            quest.completedAt = nil
            quest.trivialDone = quest.trivialDone.map { _ in false }
            result.questsReopened += 1
        }

        try context.save()
        return result
    }
}
