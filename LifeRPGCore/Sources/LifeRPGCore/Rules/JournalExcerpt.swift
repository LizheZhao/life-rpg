import Foundation

/// The beginning of what the user wrote, on one line, for a card that shows a few lines. One rule
/// for the document-based `JournalEntryDay` and `JournalDocument`.
enum JournalExcerpt {
    /// Collapses runs of whitespace (newlines included) into single spaces.
    static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// `parts` joined by a space and collapsed, cut at a word boundary when the cut has one past its
    /// first half (text with no spaces, as in Chinese, is cut at `limit` characters), with an
    /// ellipsis only when something was left out. A trailing `, ; : -` is dropped before it.
    static func cut(_ parts: [String], limit: Int) -> String {
        let line = collapse(parts.joined(separator: " "))
        guard line.count > limit else { return line }
        let head = line.prefix(limit)
        var cut = head
        if !line[line.index(line.startIndex, offsetBy: limit)].isWhitespace,
           let space = head.lastIndex(of: " "), head.distance(from: head.startIndex, to: space) >= limit / 2 {
            cut = head[..<space]
        }
        let loose = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",;:-"))
        return String(cut).trimmingCharacters(in: loose) + "\u{2026}"
    }
}
