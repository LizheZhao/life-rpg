import Foundation

/// The text handed to the on-device model for "Ask me something", written here so the rules it is
/// held to exist in one place. `JournalAsk.accept` afterwards enforces the ones a pattern can
/// catch. `JournalPromptBuilderTests` pins both texts whole, because a softened rule is the failure
/// nobody notices until the voice drifts.
public enum JournalPromptBuilder {
    /// One hand-written rule, in both languages.
    private struct Rule {
        let en: String
        let zh: String
    }

    private static let rules: [Rule] = [
        Rule(en: "Ask exactly one question, under \(JournalAsk.wordLimit) words.",
             zh: "只问一个问题，少于 \(JournalAsk.characterLimit) 个字。"),
        Rule(en: "Write it in the second person, speaking to \"you\".",
             zh: "用第二人称，直接对“你”说。"),
        Rule(en: "Ask about something that happened today or was skipped today, from the facts below.",
             zh: "问今天发生的事，或今天没做的事，依据下面的情况。"),
        Rule(en: "Give no advice.", zh: "不给建议。"),
        Rule(en: "Make no diagnosis.", zh: "不做诊断。"),
        Rule(en: "No praise or guilt. The app already tracks coins, so do not add to it.",
             zh: "不夸奖，也不让人内疚。金币的事应用已经记着，不要再多说。"),
        Rule(en: "Never ask a question that is already listed, or one close to it.",
             zh: "已经列出的问题不要再问，相近的也不要。"),
        Rule(en: "Never start with why; ask what got in the way, or what it was like.",
             zh: "不要以“为什么”开头；问是什么挡了一下，或者当时是什么样的。"),
        Rule(en: "No contrast staging such as \"not X, but Y\".",
             zh: "不要用“不是……而是……”这类对比句式。"),
        Rule(en: "No closing one-liner that repeats the point.", zh: "不要用一句话收尾来重复要点。"),
        Rule(en: "No triads for rhythm; no long dashes; no markdown.",
             zh: "不要为了节奏凑三项并列；不要用破折号；不要用 markdown。"),
        Rule(en: "Examples show tone only; never reuse their wording or sentence structure.",
             zh: "示例只是语气的参照；不要沿用它们的措辞和句式。"),
    ]

    /// How much of the entry goes in: its last characters. The on-device model has a small context
    /// window, and what was written last is what the next question should follow.
    public static let maxWritingCharacters = 1_500

    public static func instructions(language: JournalLanguage) -> String {
        switch language {
        case .en:
            return "You help someone write a short end-of-day journal. They tap a button and you give them one question to write about. Reply with the question only, as plain text.\n"
                + rules.map { "- " + $0.en }.joined(separator: "\n")
        case .zhHans:
            return "你在帮用户写一篇简短的睡前日记。用户点一下按钮，你给出一个可以写一写的问题。只回复这个问题，用纯文本。\n"
                + rules.map { "- " + $0.zh }.joined(separator: "\n")
        }
    }

    /// The prompt: the day's facts, then each section that has something in it. `writing` is nil to
    /// leave out everything the user wrote (the privacy switch), and `recent` is passed empty then
    /// too; the caller decides, so this function can not leak what it is not given.
    public static func prompt(language: JournalLanguage, signals: JournalSignals, writing: String?,
                              existing: [String], recent: [String], anchors: [String]) -> String {
        let words = Words(language)
        var sections = [words.opening + "\n\n" + words.factsHeading + "\n"
                        + facts(signals, words).map { "- " + $0 }.joined(separator: "\n")]
        if let writing {
            let kept = writing.count > maxWritingCharacters
                ? "\u{2026}" + String(writing.suffix(maxWritingCharacters)) : writing
            sections.append(words.writingHeading + "\n" + kept)
        }
        for (heading, lines) in [(words.existingHeading, existing), (words.recentHeading, recent),
                                 (words.anchorsHeading, anchors)] where !lines.isEmpty {
            sections.append(heading + "\n" + lines.map { "- " + $0 }.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    /// The entry as plain text for the prompt: a text as it is, a prompt as `Q: ...` over `A: ...`,
    /// blocks separated by a blank line. Nil when nothing is written in it.
    public static func writing(of document: JournalDocument) -> String? {
        guard !document.isEmpty else { return nil }
        return document.blocks.compactMap { block -> String? in
            let written = block.writtenText.trimmingCharacters(in: .whitespacesAndNewlines)
            switch block {
            case .text:
                return written.isEmpty ? nil : written
            case .prompt(_, let question, _, _, _):
                return "Q: " + question + "\n" + (written.isEmpty ? "A:" : "A: " + written)
            }
        }.joined(separator: "\n\n")
    }

    private static func facts(_ signals: JournalSignals, _ words: Words) -> [String] {
        var lines = [words.dayType(signals.tier), words.coins(signals.coinsEarned)]
        lines.append(words.list(words.done, signals.completed.map(words.done(_:)), none: words.nothing))
        if !signals.skipped.isEmpty {
            lines.append(words.list(words.skipped, signals.skipped.map(\.text)))
        }
        if !signals.leftOpen.isEmpty {
            lines.append(words.list(words.notDone, signals.leftOpen.map(\.text)))
        }
        return lines
    }

    /// Every sentence the prompt says, per language, so the two can not drift apart in structure.
    private struct Words {
        let language: JournalLanguage

        init(_ language: JournalLanguage) { self.language = language }

        private var zh: Bool { language == .zhHans }

        var opening: String { zh ? "为用户的日记写一个关于今天的问题。" : "Write one question for the user's journal, about today." }
        var factsHeading: String { zh ? "今天的情况：" : "Facts about today:" }
        var writingHeading: String { zh ? "用户到目前为止写的：" : "What the user has written so far:" }
        var existingHeading: String {
            zh ? "这篇日记里已经有的问题，不要再问：" : "Questions already in this entry. Do not ask these again:"
        }
        var recentHeading: String {
            zh ? "最近几篇日记里的问题，不要问得相似：" : "Questions from recent entries. Do not ask anything like these:"
        }
        var anchorsHeading: String {
            zh ? "示例，只用来参考语气，不要沿用它们的措辞和句式："
               : "Examples. They show the tone only; do not reuse their wording or sentence structure:"
        }
        var done: String { zh ? "做完的" : "Done" }
        var skipped: String { zh ? "跳过的" : "Skipped" }
        var notDone: String { zh ? "还没做的" : "Not done yet" }
        var nothing: String { zh ? "没有" : "nothing" }

        func dayType(_ tier: Tier) -> String {
            if zh {
                let word = switch tier {
                case .veryLow: "很低"
                case .low: "偏低"
                case .normal: "正常"
                case .high: "充沛"
                }
                return "今天的精力：\(word)。"
            }
            let word = switch tier {
            case .veryLow: "very low"
            case .low: "low"
            case .normal: "normal"
            case .high: "high"
            }
            return "Day type: \(word)."
        }

        func coins(_ count: Int) -> String { zh ? "赚到的金币：\(count)。" : "Coins earned: \(count)." }

        /// "Walk (+12 coins)", "A 30 minute walk (light version, +20 coins)"; a completion that paid
        /// nothing and is not light is just its text.
        func done(_ item: JournalSignals.Item) -> String {
            var notes: [String] = []
            if item.isLight { notes.append(zh ? "轻量版" : "light version") }
            if item.coins != 0 { notes.append(zh ? "+\(item.coins) 金币" : "+\(item.coins) coins") }
            guard !notes.isEmpty else { return item.subject.text }
            return zh ? item.subject.text + "（" + notes.joined(separator: "，") + "）"
                      : item.subject.text + " (" + notes.joined(separator: ", ") + ")"
        }

        func list(_ label: String, _ items: [String], none: String? = nil) -> String {
            let colon = zh ? "：" : ": "
            let separator = zh ? "；" : "; "
            let end = zh ? "。" : "."
            return label + colon + (items.isEmpty ? (none ?? "") : items.joined(separator: separator)) + end
        }
    }
}
