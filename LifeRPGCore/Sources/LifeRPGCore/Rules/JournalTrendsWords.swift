import Foundation
import NaturalLanguage

extension JournalTrends {
    /// "What this month was about": the words the period leans on that the other months do not.
    ///
    /// Only the user's own words are read (a text block and a prompt's answer, never a question).
    /// Each period of the shown kind that holds entries is one document, and a word's score is its
    /// count in the shown period times its inverse document frequency over those documents, so a
    /// word written every month, however often, does not win. With no other period to compare
    /// against the list is plain counts and says so (`Kind.mostUsed`).
    public enum Words {
        public struct Entry: Equatable, Sendable {
            public let word: String
            public let count: Int
        }

        public enum Kind: Equatable, Sendable {
            /// Ranked by how much a word stands out against the other periods.
            case distinctive
            /// Ranked by count alone: fewer than two periods have entries.
            case mostUsed
        }

        public struct Result: Equatable, Sendable {
            public let kind: Kind
            public let entries: [Entry]
        }

        /// A word said once is not what the month was about.
        static let minimumWordCount = 2
        /// Two different words in a row must repeat this often to count as a phrase ("light version").
        static let minimumPhraseCount = 3

        /// The top `limit` words of `range`, a period of the kind `period`. `days` may be the whole
        /// history: the other periods of the same kind are the rest of the corpus.
        public static func top(in days: [JournalEntryDay], period: Period, range: DayRange,
                               language: JournalLanguage, limit: Int = 5,
                               timeZone: TimeZone = .current) -> Result {
            let written = JournalTrends.written(days)
            let mineDays = written.filter { range.contains($0.dayKey) }
            let mine = tally(mineDays, language: language)
            let others = Dictionary(grouping: written.filter { !range.contains($0.dayKey) }) {
                JournalTrends.range(of: period, containing: $0.dayKey, in: timeZone)?.first ?? $0.dayKey
            }.values.map { tally($0, language: language) }
            let kind: Kind = !mineDays.isEmpty && !others.isEmpty ? .distinctive : .mostUsed
            guard limit > 0 else { return Result(kind: kind, entries: []) }

            // Repeating pairs are candidates of their own, and an occurrence inside one is theirs
            // rather than its words', so "light version" is not also "light" and "version".
            let phrases = mine.pairs.filter { $0.value >= minimumPhraseCount }
            func withoutPhrases(_ tally: Tally) -> [String: Int] {
                var words = tally.words
                for phrase in phrases.keys {
                    for part in phrase.split(separator: " ") {
                        words[String(part)] = max(0, (words[String(part)] ?? 0) - (tally.pairs[phrase] ?? 0))
                    }
                }
                return words
            }

            struct Candidate {
                let key: String
                let count: Int
                /// Documents of the corpus that have it, the period's own included.
                let documents: Int
            }
            let myWords = withoutPhrases(mine)
            let otherWords = others.map(withoutPhrases)
            let candidates = myWords.filter { $0.value >= minimumWordCount }.map { key, count in
                Candidate(key: key, count: count, documents: 1 + otherWords.filter { ($0[key] ?? 0) > 0 }.count)
            } + phrases.map { key, count in
                Candidate(key: key, count: count, documents: 1 + others.filter { ($0.pairs[key] ?? 0) > 0 }.count)
            }

            let corpusSize = Double(others.count + 1)
            let scored = candidates.map { c -> (Candidate, Double) in
                guard kind == .distinctive else { return (c, Double(c.count)) }
                // Smoothed, so a word in every document still scores its count rather than nothing.
                return (c, Double(c.count) * (log((corpusSize + 1) / (Double(c.documents) + 1)) + 1))
            }
            let top = scored
                .sorted { ($0.1, $0.0.count, $1.0.key) > ($1.1, $1.0.count, $0.0.key) }
                .prefix(limit)
                .map { Entry(word: display($0.0.key, language: language), count: $0.0.count) }
            return Result(kind: kind, entries: top)
        }

        private static func display(_ key: String, language: JournalLanguage) -> String {
            language == .zhHans ? key.replacingOccurrences(of: " ", with: "") : key
        }

        /// Occurrences of every kept word, of every pair of kept words that are neighbours in the
        /// text, and how many kept words there were in all.
        struct Tally {
            var words: [String: Int] = [:]
            var pairs: [String: Int] = [:]
            var total = 0
        }

        static func tally(_ days: [JournalEntryDay], language: JournalLanguage) -> Tally {
            var tally = Tally()
            for day in days {
                for block in day.document.blocks {
                    for paragraph in block.writtenText.split(whereSeparator: \.isNewline) {
                        var previous: String?
                        for token in tokens(in: String(paragraph), language: language) {
                            guard isContent(token.text, language: language) else {
                                previous = nil
                                continue
                            }
                            tally.words[token.text, default: 0] += 1
                            tally.total += 1
                            if token.joinsPrevious, let previous, previous != token.text {
                                tally.pairs[previous + " " + token.text, default: 0] += 1
                            }
                            previous = token.text
                        }
                    }
                }
            }
            return tally
        }

        /// A word that can say something: it has a letter (so no numbers, times or emoji), is not a
        /// stop word, and in English is three letters or more.
        static func isContent(_ token: String, language: JournalLanguage) -> Bool {
            guard token.contains(where: \.isLetter), !isStopWord(token, language: language) else { return false }
            return language == .zhHans || token.count >= 3
        }

        struct Token: Equatable {
            let text: String
            /// Only whitespace, or nothing, between this token and the one before it: a comma or a
            /// full stop in between ends a phrase.
            let joinsPrevious: Bool
        }

        /// The lowercased words of one paragraph, apostrophes straightened. The system tokenizer
        /// knows where Chinese words end.
        static func tokens(in paragraph: String, language: JournalLanguage) -> [Token] {
            let text = paragraph.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            return systemTokens(in: text, language: language)
        }

        private static func systemTokens(in text: String, language: JournalLanguage) -> [Token] {
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.string = text
            tokenizer.setLanguage(language == .zhHans ? .simplifiedChinese : .english)
            var out: [Token] = []
            var previousEnd: String.Index?
            tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
                let joins = previousEnd.map { text[$0..<range.lowerBound].allSatisfy(\.isWhitespace) } ?? false
                out.append(Token(text: String(text[range]), joinsPrevious: joins))
                previousEnd = range.upperBound
                return true
            }
            return out
        }
    }
}
