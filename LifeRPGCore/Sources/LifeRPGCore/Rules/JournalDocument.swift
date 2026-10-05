import Foundation

/// A day's journal as the editor holds it: an ordered list of blocks and the rules that read it.
/// A pure value, so what the editor shows, what is saved and what the lists read cannot disagree.
/// The editing operations are in `JournalDocument+Editing.swift`.
public struct JournalDocument: Equatable, Sendable {
    public var blocks: [JournalBlock]

    public init(blocks: [JournalBlock] = []) {
        self.blocks = blocks
    }

    /// The user's words (`JournalWords.count`) in every text and every answer, never a question.
    public var wordCount: Int {
        blocks.reduce(0) { $0 + JournalWords.count($1.writtenText) }
    }

    /// Characters in every text and every answer, whitespace included.
    public var characterCount: Int {
        blocks.reduce(0) { $0 + $1.writtenText.count }
    }

    /// Nothing but whitespace in any text or answer. Unanswered prompts alone do not make an entry,
    /// and neither does a page of spaces and newlines, which would be saved with a blank preview.
    public var isEmpty: Bool {
        blocks.allSatisfy { $0.writtenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public func containsFixedKey(_ key: JournalFixedKey) -> Bool {
        blocks.contains { if case .prompt(_, _, _, _, key) = $0 { true } else { false } }
    }

    public var llmPromptCount: Int {
        blocks.filter { if case .prompt(_, _, _, .llm, _) = $0 { true } else { false } }.count
    }

    public var promptCount: Int {
        blocks.filter { if case .prompt = $0 { true } else { false } }.count
    }

    /// The questions, in order.
    public var questions: [String] {
        blocks.compactMap { if case .prompt(_, let question, _, _, _) = $0 { question } else { nil } }
    }

    /// What is worth saving: empty texts dropped, then adjacent texts merged (joined by a newline,
    /// keeping the first one's id). Prompts never merge and keep an empty answer, so a question
    /// pulled in and skipped stays visible. A document with no characters normalizes to no blocks.
    public func normalized() -> JournalDocument {
        guard !isEmpty else { return JournalDocument() }
        var out: [JournalBlock] = []
        for block in blocks {
            guard case .text(_, let text) = block else {
                out.append(block)
                continue
            }
            guard !text.isEmpty else { continue }
            if case .text(let lastID, let lastText)? = out.last {
                out[out.count - 1] = .text(id: lastID, text: lastText + "\n" + text)
            } else {
                out.append(block)
            }
        }
        return JournalDocument(blocks: out)
    }

    /// What goes to Apple Journal: each block in order, a text as its words, a prompt as its question
    /// on one line and its answer on the next, blocks separated by a blank line. A prompt with no
    /// answer and a text with only whitespace are left out, and every piece is trimmed at its ends.
    /// Plain text has no bold, so the question is not marked.
    public func plainText() -> String {
        blocks.compactMap { block -> String? in
            let words = block.writtenText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !words.isEmpty else { return nil }
            guard case .prompt(_, let question, _, _, _) = block else { return words }
            return question + "\n" + words
        }.joined(separator: "\n\n")
    }

    /// The first thing written, on one line, for a list row: whitespace collapsed, cut at `limit`
    /// characters with an ellipsis only when something was left out.
    public func preview(limit: Int = 80) -> String {
        guard let first = blocks.lazy.map({ JournalExcerpt.collapse($0.writtenText) }).first(where: { !$0.isEmpty })
        else { return "" }
        guard first.count > limit else { return first }
        return first.prefix(limit).trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }

    /// The beginning of what was written across blocks, for a card (`JournalExcerpt.cut`).
    public func excerpt(limit: Int) -> String {
        JournalExcerpt.cut(blocks.map(\.writtenText), limit: limit)
    }
}
