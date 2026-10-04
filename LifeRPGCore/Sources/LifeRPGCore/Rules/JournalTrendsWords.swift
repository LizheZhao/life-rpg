import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

extension JournalTrends {
    /// "What this month was about": the words the period leans on that the other months do not.
    ///
    /// Only the user's own words are read (the answers, never the question lines, and never the
    /// starter phrase the page typed for them). A word's score is its count in the period times how
    /// much more often it turns up there than elsewhere, so a word written every month, however
    /// often, does not win.
    public enum Words {
        public struct Entry: Equatable, Sendable {
            public let word: String
            public let count: Int
        }

        /// Added to a word's relative frequency in the other months before dividing by it, so a
        /// word they never use scores high without dividing by zero. About one use in a thousand
        /// words: a word the period uses at that rate everywhere else weighs next to half a word of
        /// the same count that is new, one it uses never weighs six times as much.
        static let smoothing = 0.001
        /// A word said once is not what the month was about.
        static let minimumWordCount = 2
        /// Two different words in a row must repeat this often to count as a phrase ("light version").
        static let minimumPhraseCount = 3

        public static func distinctive(period: [JournalDay], others: [JournalDay], language: JournalLanguage,
                                       limit: Int = 5) -> [Entry] {
            guard limit > 0 else { return [] }
            let mine = tally(period, language: language)
            let theirs = tally(others, language: language)

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
                let otherCount: Int
            }
            let myWords = withoutPhrases(mine)
            let theirWords = withoutPhrases(theirs)
            let candidates = myWords.filter { $0.value >= minimumWordCount }
                .map { Candidate(key: $0.key, count: $0.value, otherCount: theirWords[$0.key] ?? 0) }
                + phrases.map { Candidate(key: $0.key, count: $0.value, otherCount: theirs.pairs[$0.key] ?? 0) }

            let scored = candidates.map { c -> (Candidate, Double) in
                let mineRate = Double(c.count) / Double(max(1, mine.total))
                let theirRate = Double(c.otherCount) / Double(max(1, theirs.total))
                return (c, Double(c.count) * mineRate / (theirRate + smoothing))
            }
            return scored
                .sorted { ($0.1, $0.0.count, $1.0.key) > ($1.1, $1.0.count, $0.0.key) }
                .prefix(limit)
                .map { Entry(word: display($0.0.key, language: language), count: $0.0.count) }
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

        static func tally(_ days: [JournalDay], language: JournalLanguage) -> Tally {
            var tally = Tally()
            for day in days {
                for turn in JournalComposer.written(day.turns) {
                    for paragraph in turn.answer.split(whereSeparator: \.isNewline) {
                        var previous: String?
                        for token in tokens(in: JournalStarters.strippingStarter(from: String(paragraph)),
                                            language: language) {
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
        /// knows where Chinese words end; without it a plain split is the fallback.
        static func tokens(in paragraph: String, language: JournalLanguage) -> [Token] {
            let text = paragraph.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            #if canImport(NaturalLanguage)
            return systemTokens(in: text, language: language)
            #else
            return fallbackTokens(in: text)
            #endif
        }

        #if canImport(NaturalLanguage)
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
        #endif

        /// Letter runs, an apostrophe or hyphen between letters keeping one together ("don't"). A run
        /// of Chinese characters is cut into overlapping pairs, which is crude but never wrong about
        /// where a word is not, and pairs are not joined into phrases (they already overlap).
        static func fallbackTokens(in text: String) -> [Token] {
            var out: [Token] = []
            var latin = ""
            var cjk: [Character] = []
            // The last token was a letter run and only whitespace has come since.
            var joinable = false
            func flushLatin() {
                guard !latin.isEmpty else { return }
                out.append(Token(text: latin, joinsPrevious: joinable))
                latin = ""
                joinable = true
            }
            func flushCJK() {
                guard !cjk.isEmpty else { return }
                let pieces = cjk.count == 1 ? [String(cjk)] : (0..<cjk.count - 1).map { String(cjk[$0...$0 + 1]) }
                out += pieces.map { Token(text: $0, joinsPrevious: false) }
                cjk = []
                joinable = false
            }
            let characters = Array(text)
            for (i, ch) in characters.enumerated() {
                if isCJK(ch) {
                    flushLatin()
                    cjk.append(ch)
                } else if ch.isLetter || ch.isNumber {
                    flushCJK()
                    latin.append(ch)
                } else if ch == "'" || ch == "-", !latin.isEmpty, i + 1 < characters.count, characters[i + 1].isLetter {
                    latin.append(ch)
                } else {
                    flushLatin()
                    flushCJK()
                    if !ch.isWhitespace { joinable = false }
                }
            }
            flushLatin()
            flushCJK()
            return out
        }

        private static func isCJK(_ ch: Character) -> Bool {
            ch.unicodeScalars.contains { $0.properties.isIdeographic }
        }
    }
}
