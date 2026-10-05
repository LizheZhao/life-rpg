import Foundation

/// Where the cursor goes after an edit. `offset` counts `Character`s (extended grapheme clusters, so
/// an emoji or an accented letter is one) from the start of the block's editable string: a text's
/// words, or a prompt's answer.
public struct BlockFocus: Equatable, Sendable {
    public let blockID: UUID
    public let offset: Int

    public init(blockID: UUID, offset: Int) {
        self.blockID = blockID
        self.offset = offset
    }
}

/// The result of an editing operation. `focus` is nil only when the edit left no block to focus.
public struct JournalEdit: Equatable, Sendable {
    public let document: JournalDocument
    public let focus: BlockFocus?
}

/// A prompt about to be inserted: its question and where it came from. The answer starts empty.
public struct JournalPromptSeed: Equatable, Sendable {
    public let question: String
    public let source: PromptSource
    public let fixedKey: JournalFixedKey?

    public init(question: String, source: PromptSource, fixedKey: JournalFixedKey? = nil) {
        self.question = question
        self.source = source
        self.fixedKey = fixedKey
    }

    /// What a chip inserts.
    public static func fixed(_ key: JournalFixedKey, language: JournalLanguage) -> JournalPromptSeed {
        JournalPromptSeed(question: key.question(language: language), source: .fixed, fixedKey: key)
    }
}

/// The editor's operations on the document, each returning the new document and the cursor. They
/// return nil when there is nothing to do: an unknown block, a chip already in the document, a
/// backspace on an answer that is not empty. New blocks take their id from `makeID`.
extension JournalDocument {
    /// A prompt goes after the block the cursor is in (`atBlock`, nil meaning the end of the
    /// document). In the middle of a text the text is split at `offset` and the prompt goes between
    /// the halves; at the start of a text it goes before it, at the end (or in an empty text) after
    /// it, so no empty half is created. The cursor lands in the new, empty answer.
    public func insertingPrompt(_ seed: JournalPromptSeed, atBlock blockID: UUID?, offset: Int,
                                makeID: () -> UUID = UUID.init) -> JournalEdit? {
        if let key = seed.fixedKey, containsFixedKey(key) { return nil }
        let promptID = makeID()
        let prompt = JournalBlock.prompt(id: promptID, question: seed.question, answer: "",
                                         source: seed.source, fixedKey: seed.fixedKey)
        var blocks = self.blocks
        if let blockID {
            guard let i = blocks.firstIndex(where: { $0.id == blockID }) else { return nil }
            if case .text(let id, let text) = blocks[i], !text.isEmpty {
                let cursor = min(max(offset, 0), text.count)
                if cursor == 0 {
                    blocks.insert(prompt, at: i)
                } else if cursor == text.count {
                    blocks.insert(prompt, at: i + 1)
                } else {
                    blocks[i] = .text(id: id, text: String(text.prefix(cursor)))
                    blocks.insert(contentsOf: [prompt, .text(id: makeID(), text: String(text.dropFirst(cursor)))],
                                  at: i + 1)
                }
            } else {
                blocks.insert(prompt, at: i + 1)
            }
        } else {
            blocks.append(prompt)
        }
        return JournalEdit(document: JournalDocument(blocks: blocks), focus: BlockFocus(blockID: promptID, offset: 0))
    }

    /// Return at the end of a prompt's answer: a new empty text below it, focused, so the user is
    /// back in free text.
    public func returningAtEndOfAnswer(promptID: UUID, makeID: () -> UUID = UUID.init) -> JournalEdit? {
        guard let i = promptIndex(promptID) else { return nil }
        let id = makeID()
        var blocks = self.blocks
        blocks.insert(.text(id: id, text: ""), at: i + 1)
        return JournalEdit(document: JournalDocument(blocks: blocks), focus: BlockFocus(blockID: id, offset: 0))
    }

    /// Backspace at the start of an empty answer deletes the whole prompt. The cursor goes to the
    /// end of the block before it, or the start of the block after it when it was the first.
    public func backspaceAtStartOfEmptyAnswer(promptID: UUID) -> JournalEdit? {
        guard let i = promptIndex(promptID), case .prompt(_, _, let answer, _, _) = blocks[i],
              answer.isEmpty else { return nil }
        var blocks = self.blocks
        blocks.remove(at: i)
        let focus: BlockFocus? = if i > 0 {
            BlockFocus(blockID: blocks[i - 1].id, offset: blocks[i - 1].writtenText.count)
        } else if let next = blocks.first {
            BlockFocus(blockID: next.id, offset: 0)
        } else {
            nil
        }
        return JournalEdit(document: JournalDocument(blocks: blocks), focus: focus)
    }

    /// "Remove question": the prompt becomes a text with the same id, keeping the answer. The cursor
    /// goes to the end of it.
    public func removingQuestion(promptID: UUID) -> JournalEdit? {
        guard let i = promptIndex(promptID), case .prompt(let id, _, let answer, _, _) = blocks[i] else { return nil }
        var blocks = self.blocks
        blocks[i] = .text(id: id, text: answer)
        return JournalEdit(document: JournalDocument(blocks: blocks), focus: BlockFocus(blockID: id, offset: answer.count))
    }

    private func promptIndex(_ id: UUID) -> Int? {
        blocks.firstIndex { if case .prompt = $0 { $0.id == id } else { false } }
    }
}
