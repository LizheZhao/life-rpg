import Foundation
import SwiftData

/// One day's journal: a single document, as the editor, the reader and the lists see it. Guided and
/// free writing are not two kinds of entry; a prompt is a block inside the one body.
///
/// The blocks are one JSON array in `blocksJSON` (the shape is on `JournalBlock`), so the whole
/// document is read and written together, the way the editor autosaves it. There is one row per
/// `dayKey`, kept by `JournalEntries.save`, not by the store (no `@Attribute(.unique)`, which
/// CloudKit does not allow). A day with nothing written has no row at all.
///
/// Nothing is cached: the word count and the preview are read off the blocks every time. `doneAt`
/// is cosmetic. It is the first time the user tapped Done, and nothing reads it to decide whether
/// the entry may be edited.
///
/// Impact on existing data: a new model only (`SchemaV8`), which lightweight migration infers, so
/// no stored row of any other model is touched and a store that has no entries simply has none.
/// `JournalTurn` and its rows stay exactly as they are; `JournalMigration` copies them into
/// entries on request. CloudKit-ready: every property is defaulted or optional, nothing is unique.
@Model public final class JournalEntry {
    public var id: UUID = UUID()
    /// The app day the entry belongs to (`LifeCalendar.dayStartHour`), fixed when the row is made,
    /// so a time zone change later in the day does not move it.
    public var dayKey: String = ""
    /// `JournalBlock.encodeAll` of the document's blocks.
    public var blocksJSON: String = "[]"
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    /// When the user first tapped Done; nil is a draft.
    public var doneAt: Date?

    public init() {}

    public var blocks: [JournalBlock] {
        get { JournalBlock.decodeAll(blocksJSON) }
        set { blocksJSON = JournalBlock.encodeAll(newValue) }
    }

    public var document: JournalDocument { JournalDocument(blocks: blocks) }

    public var isDone: Bool { doneAt != nil }

    /// `JournalDocument.wordCount`: the user's words, never a question.
    public var wordCount: Int { document.wordCount }
}
