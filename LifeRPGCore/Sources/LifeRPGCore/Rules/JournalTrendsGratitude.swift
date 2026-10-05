import Foundation

extension JournalTrends {
    /// "Grateful for, most often": what the user answered to the Grateful for chip
    /// (`JournalFixedKey.gratefulFor`), counted across days. Free text and every other prompt,
    /// the model's included, are left alone: the page counts what was asked as gratitude.
    public enum Gratitude {
        public struct Phrase: Equatable, Sendable {
            public let text: String
            public let count: Int
        }

        /// A longer item is a sentence, not a thing someone is grateful for.
        static let maximumLength = 40

        /// The commonest items first, then the most recently written, then alphabetically so the
        /// order is the same every time.
        public static func phrases(in days: [JournalEntryDay], limit: Int = 7) -> [Phrase] {
            guard limit > 0 else { return [] }
            struct Seen {
                var count = 0
                var latestDay = ""
                var casings: [String: (count: Int, latestDay: String)] = [:]
            }
            var seen: [String: Seen] = [:]
            for day in days {
                for block in day.document.blocks {
                    guard case .prompt(_, _, let answer, _, .gratefulFor) = block else { continue }
                    for item in items(inAnswer: answer) {
                        let key = item.lowercased()
                        seen[key, default: Seen()].count += 1
                        seen[key]!.latestDay = max(seen[key]!.latestDay, day.dayKey)
                        let casing = seen[key]!.casings[item] ?? (0, "")
                        seen[key]!.casings[item] = (casing.count + 1, max(casing.latestDay, day.dayKey))
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

        /// The separate things one answer names. Items end at a comma, semicolon, `、`, `，`, `；`, " and "
        /// (only with spaces around it, so "sand" stays whole), `和`, a line break or a sentence end.
        /// A full stop ends a sentence only at the end of the text or before whitespace, so "3.5 hours"
        /// stays whole.
        static func items(inAnswer answer: String) -> [String] {
            let text = Array(answer.replacingOccurrences(of: " and ", with: ",", options: .caseInsensitive))
            var items: [String] = []
            var current = ""
            for (index, ch) in text.enumerated() {
                let next = index + 1 < text.count ? text[index + 1] : nil
                let ends = ch.isNewline || ",;，；、和!?。！？".contains(ch)
                    || (ch == "." && (next?.isWhitespace ?? true))
                if ends {
                    items.append(current)
                    current = ""
                } else {
                    current.append(ch)
                }
            }
            items.append(current)
            return items.compactMap(clean)
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
