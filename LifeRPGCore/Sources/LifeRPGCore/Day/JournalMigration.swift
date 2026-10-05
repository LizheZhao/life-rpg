import Foundation
import SwiftData

/// Copies the turn-based journal into day documents.
///
/// A day that has turns and no entry becomes one entry, built from its turns by `index`; a day that
/// already has an entry is left alone, so running it again creates nothing. It never deletes or
/// edits a turn: the old rows stay for a later release to drop. Does not save.
///
/// Run it once rather than on every launch. An entry the user later clears is deleted, and a
/// turn-only day looks the same as one that was never migrated, so the next run would bring it back.
public enum JournalMigration {
    /// Returns how many entries were created.
    @discardableResult
    public static func migrateTurns(in context: ModelContext) throws -> Int {
        let turns = try context.fetch(FetchDescriptor<JournalTurn>())
        let have = Set(try JournalEntries.all(in: context).map(\.dayKey))
        var created = 0
        for (dayKey, rows) in Dictionary(grouping: turns, by: \.dayKey).sorted(by: { $0.key < $1.key })
        where !have.contains(dayKey) {
            guard let entry = entry(from: rows, dayKey: dayKey) else { continue }
            context.insert(entry)
            created += 1
        }
        return created
    }

    /// The closing turn, whether it answers the closing question or is free writing, ended the day.
    /// A free-writing turn that is blank (the page was cleared) closed nothing.
    static func isClosed(_ turns: [JournalTurn]) -> Bool {
        turns.contains { $0.kind == .closing && !$0.isBlankFreeWriting }
    }

    /// One day's turns as an entry, or nil when nothing is written in them.
    ///
    /// An answered question becomes a prompt with its answer, a skipped or misfit one a prompt with
    /// no answer (it stays visible as passed), free writing a text, and the safety line is dropped.
    /// A model-worded question is `llm`, a pool question `fixed`, with no `fixedKey` because the pool
    /// rows are not the four chips. `createdAt` is the first question asked and `updatedAt` the last
    /// answer; `doneAt` is that last answer when the day was closed (`isClosed`).
    static func entry(from rows: [JournalTurn], dayKey: String) -> JournalEntry? {
        let ordered = rows.sorted { $0.index < $1.index }
        var blocks: [JournalBlock] = []
        for turn in ordered where turn.kind != .safety {
            if turn.isFreeWriting {
                if !turn.isBlankFreeWriting { blocks.append(.text(id: UUID(), text: turn.answer)) }
            } else {
                blocks.append(.prompt(id: UUID(), question: turn.questionText,
                                      answer: turn.outcome == .answered ? turn.answer : "",
                                      source: turn.source == .model ? .llm : .fixed, fixedKey: nil))
            }
        }
        let document = JournalDocument(blocks: blocks).normalized()
        guard !document.isEmpty, let first = ordered.map(\.askedAt).min(),
              let last = ordered.map(\.answeredAt).max() else { return nil }
        let row = JournalEntry()
        row.dayKey = dayKey
        row.blocksJSON = JournalBlock.encodeAll(document.blocks)
        row.createdAt = first
        row.updatedAt = last
        row.doneAt = isClosed(ordered) ? last : nil
        return row
    }
}
