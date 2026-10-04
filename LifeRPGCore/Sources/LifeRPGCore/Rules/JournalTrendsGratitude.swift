import Foundation

extension JournalTrends {
    /// "Grateful for, most often": what the user wrote after the "Grateful for" starter
    /// (`JournalStarters.grateful`, in either language), counted across days.
    public enum Gratitude {
        public struct Phrase: Equatable, Sendable {
            public let text: String
            public let count: Int
        }

        /// A longer item is a sentence, not a thing someone is grateful for.
        static let maximumLength = 40

        /// The commonest items first, then the most recently written, then alphabetically so the
        /// order is the same every time. The starter matches in both languages whichever one the
        /// system is in: someone can write in either.
        public static func phrases(in days: [JournalDay], limit: Int = 7) -> [Phrase] {
            guard limit > 0 else { return [] }
            struct Seen {
                var count = 0
                var latestDay = ""
                var casings: [String: (count: Int, latestDay: String)] = [:]
            }
            var seen: [String: Seen] = [:]
            for day in days {
                for turn in JournalComposer.written(day.turns) {
                    for paragraph in turn.answer.split(whereSeparator: \.isNewline) {
                        for item in items(inParagraph: String(paragraph)) {
                            let key = item.lowercased()
                            seen[key, default: Seen()].count += 1
                            seen[key]!.latestDay = max(seen[key]!.latestDay, day.dayKey)
                            let casing = seen[key]!.casings[item] ?? (0, "")
                            seen[key]!.casings[item] = (casing.count + 1, max(casing.latestDay, day.dayKey))
                        }
                    }
                }
            }
            return seen
                .sorted { ($1.value.count, $1.value.latestDay, $0.key) < ($0.value.count, $0.value.latestDay, $1.key) }
                .prefix(limit)
                .map { key, value in
                    let casing = value.casings.max {
                        ($0.value.count, $0.value.latestDay, $1.key) < ($1.value.count, $1.value.latestDay, $0.key)
                    }?.key ?? key
                    return Phrase(text: casing, count: value.count)
                }
        }

        /// What follows the starter in one paragraph, up to the first sentence end, as separate
        /// things. Empty for a paragraph that does not begin with the starter.
        static func items(inParagraph paragraph: String) -> [String] {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            let english = JournalStarters.grateful.en
            let chinese = JournalStarters.grateful.zh
            var rest: Substring
            let isChinese: Bool
            var separators = CharacterSet(charactersIn: ",;，；、")
            if let match = trimmed.range(of: english, options: [.anchored, .caseInsensitive]),
               trimmed[match.upperBound...].first.map({ !$0.isLetter && !$0.isNumber }) ?? true {
                rest = trimmed[match.upperBound...]
                isChinese = false
            } else if trimmed.hasPrefix(chinese) {
                rest = trimmed.dropFirst(chinese.count)
                separators.insert("和")
                isChinese = true
            } else {
                return []
            }
            while let first = rest.first, first.isWhitespace || first == ":" || first == "：" { rest = rest.dropFirst() }

            var sentence = String(firstSentence(of: rest))
            // "and" splits only in English and "和" only in Chinese: each is an ordinary part of a
            // word in the other ("sand", "和平").
            if !isChinese {
                sentence = sentence.replacingOccurrences(of: " and ", with: ",", options: .caseInsensitive)
            }
            return sentence.components(separatedBy: separators).compactMap(clean)
        }

        /// Up to the first `.`, `!`, `?`, `。`, `！` or `？`. A full stop counts only at the end of the
        /// text or before whitespace, so "3.5 hours" stays whole.
        private static func firstSentence(of text: Substring) -> Substring {
            var index = text.startIndex
            while index < text.endIndex {
                let ch = text[index]
                let next = text.index(after: index)
                if "!?。！？".contains(ch) { return text[..<index] }
                if ch == ".", next == text.endIndex || text[next].isWhitespace { return text[..<index] }
                index = next
            }
            return text
        }

        private static let trimmed = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ".,;:!?。，；：！？…\"'“”‘’()（）"))

        private static func clean(_ raw: String) -> String? {
            var item = raw.trimmingCharacters(in: trimmed)
            if item.range(of: "and ", options: [.anchored, .caseInsensitive]) != nil { item = String(item.dropFirst(4)) }
            item = item.trimmingCharacters(in: trimmed)
            return item.isEmpty || item.count > maximumLength ? nil : item
        }
    }
}
