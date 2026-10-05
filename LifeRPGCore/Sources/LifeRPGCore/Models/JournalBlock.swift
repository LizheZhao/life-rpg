import Foundation

/// Who wrote a prompt's question: the on-device model, or one of the fixed chips.
public enum PromptSource: String, Codable, CaseIterable, Sendable {
    case llm, fixed
}

/// One block of a day's journal document (`JournalEntry`). The document is an ordered list of
/// these: free text, and prompts, a question with the user's answer under it.
///
/// **Stored shape.** The blocks of an entry are one JSON array in `JournalEntry.blocksJSON`, and the
/// same objects are exported as `journalEntries[].blocks`:
///
///     {"type":"text","id":"<uuid>","text":"..."}
///     {"type":"prompt","id":"<uuid>","question":"...","answer":"...","source":"llm"|"fixed","fixedKey":"gratefulFor"}
///
/// `fixedKey` is left out when there is none. Keys are written sorted so equal documents give equal
/// strings, which is what lets a save tell "nothing changed" from a real edit.
///
/// Reading is forgiving, because a block the build cannot read must not take the whole day with it:
/// `decodeAll` drops a block that is not one of the two shapes and reads an unknown `fixedKey` as
/// none (the answer survives). Anything that is not a JSON array reads as an empty document. It
/// never throws and never crashes. `isValidJSON` is the strict reading, for the store audit.
public enum JournalBlock: Equatable, Sendable {
    case text(id: UUID, text: String)
    case prompt(id: UUID, question: String, answer: String, source: PromptSource, fixedKey: JournalFixedKey?)

    public var id: UUID {
        switch self {
        case .text(let id, _), .prompt(let id, _, _, _, _): id
        }
    }

    /// What the user wrote in the block: a text's words, a prompt's answer. Never the question.
    public var writtenText: String {
        switch self {
        case .text(_, let text): text
        case .prompt(_, _, let answer, _, _): answer
        }
    }
}

extension JournalBlock: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, id, text, question, answer, source, fixedKey
    }

    private enum Kind: String, Codable { case text, prompt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id)
        switch try c.decode(Kind.self, forKey: .type) {
        case .text:
            self = .text(id: id, text: try c.decode(String.self, forKey: .text))
        case .prompt:
            // An unknown key (from a build that has more chips) is not worth losing the answer for.
            let key = (try? c.decodeIfPresent(JournalFixedKey.self, forKey: .fixedKey)) ?? nil
            self = .prompt(id: id, question: try c.decode(String.self, forKey: .question),
                           answer: try c.decode(String.self, forKey: .answer),
                           source: try c.decode(PromptSource.self, forKey: .source), fixedKey: key)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let id, let text):
            try c.encode(Kind.text, forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(text, forKey: .text)
        case .prompt(let id, let question, let answer, let source, let fixedKey):
            try c.encode(Kind.prompt, forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(question, forKey: .question)
            try c.encode(answer, forKey: .answer)
            try c.encode(source, forKey: .source)
            try c.encodeIfPresent(fixedKey, forKey: .fixedKey)
        }
    }
}

extension JournalBlock {
    /// The array as the JSON string `JournalEntry.blocksJSON` holds.
    public static func encodeAll(_ blocks: [JournalBlock]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(blocks) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    /// The forgiving reading described above.
    public static func decodeAll(_ json: String) -> [JournalBlock] {
        let items = try? JSONDecoder().decode([Lenient].self, from: Data(json.utf8))
        return items?.compactMap(\.block) ?? []
    }

    /// Whether `json` is an array of nothing but readable blocks.
    public static func isValidJSON(_ json: String) -> Bool {
        (try? JSONDecoder().decode([JournalBlock].self, from: Data(json.utf8))) != nil
    }

    private struct Lenient: Decodable {
        let block: JournalBlock?
        init(from decoder: Decoder) throws { block = try? JournalBlock(from: decoder) }
    }
}
