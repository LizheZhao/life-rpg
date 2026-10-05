import Foundation
import SwiftData

/// Reading and writing the day documents (`JournalEntry`).
///
/// One row per `dayKey`, kept here: `save` finds the day's row before it makes one. Nothing locks:
/// `markDone` records that Done was tapped and a saved entry stays editable. Does not save the
/// context, like the other services; the caller saves once.
public enum JournalEntries {
    /// The day the editor opened from Today writes to: the app day of `now`. The spec's "between
    /// 00:00 and 04:00 it is still last night" is this day boundary, which is 05:00.
    public static func entryDayKey(now: Date, timeZone: TimeZone = .current) -> String {
        now.dayKey(in: timeZone)
    }

    /// The day's row, or nil when nothing was ever saved for it (or it was cleared).
    public static func entry(on dayKey: String, in context: ModelContext) throws -> JournalEntry? {
        try context.fetch(FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.dayKey == dayKey },
            sortBy: [SortDescriptor(\.createdAt)])).first
    }

    /// Every entry, oldest day first.
    public static func all(in context: ModelContext) throws -> [JournalEntry] {
        try context.fetch(FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.dayKey)]))
    }

    /// Saves the editor's blocks as the day's entry and returns it.
    ///
    /// The blocks are normalized first (`JournalDocument.normalized`). A document with no character
    /// in it deletes the day's row if there is one and returns nil, so the calendar and Trends see
    /// absence, not a blank entry. Otherwise the row is created or rewritten, keeping `createdAt` and
    /// `doneAt`. Saving what is already stored changes nothing, `updatedAt` included, so opening and
    /// closing an entry does not move the time it was written.
    @discardableResult
    public static func save(_ blocks: [JournalBlock], on dayKey: String, in context: ModelContext,
                            now: Date) throws -> JournalEntry? {
        let document = JournalDocument(blocks: blocks).normalized()
        let existing = try entry(on: dayKey, in: context)
        guard !document.isEmpty else {
            if let existing { context.delete(existing) }
            return nil
        }
        let json = JournalBlock.encodeAll(document.blocks)
        if let existing {
            if existing.blocksJSON != json {
                existing.blocksJSON = json
                existing.updatedAt = now
            }
            return existing
        }
        let row = JournalEntry()
        row.dayKey = dayKey
        row.blocksJSON = json
        row.createdAt = now
        row.updatedAt = now
        context.insert(row)
        return row
    }

    /// Done: sets `doneAt` the first time and never clears it. Nil when the day has no row (an empty
    /// entry has nothing to mark).
    @discardableResult
    public static func markDone(on dayKey: String, in context: ModelContext, now: Date) throws -> JournalEntry? {
        guard let row = try entry(on: dayKey, in: context) else { return nil }
        if row.doneAt == nil { row.doneAt = now }
        return row
    }
}
