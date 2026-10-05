import Foundation
@testable import LifeRPGCore

/// Blocks with readable ids for the document tests: `id(1)` is always the same UUID.
enum EntryFixtures {
    static func id(_ n: Int) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-" + String(format: "%012d", n))!
    }

    static func text(_ n: Int, _ text: String) -> JournalBlock { .text(id: id(n), text: text) }

    static func prompt(_ n: Int, _ question: String = "Q", answer: String = "", source: PromptSource = .fixed,
                       key: JournalFixedKey? = nil) -> JournalBlock {
        .prompt(id: id(n), question: question, answer: answer, source: source, fixedKey: key)
    }

    static func doc(_ blocks: JournalBlock...) -> JournalDocument { JournalDocument(blocks: blocks) }

    /// Hands out `id(first)`, `id(first + 1)`, ... for the operations that create blocks.
    final class Ids {
        private var next: Int
        init(from first: Int) { next = first }
        func make() -> UUID { defer { next += 1 }; return EntryFixtures.id(next) }
    }
}
