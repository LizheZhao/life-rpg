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
        Rule(en: "Pick one specific thing from the facts below: something done, something not done or skipped, or something finished ahead of time. A specific thing beats a general question about the day.",
             zh: "从下面的情况里挑一件具体的事来问：做完的、没做或跳过的、或者提前完成的。具体的事比笼统地问这一天更好。"),
        Rule(en: "When something hard or the epic was finished early, you may ask what finishing it felt like.",
             zh: "如果提前完成了困难的任务或 Epic，可以问完成时是什么感觉。"),
        Rule(en: "When something was not done or skipped, ask what got in the way, without blame.",
             zh: "如果有事没做或跳过了，问是什么挡住了，不带责备。"),
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
    /// too; the caller decides, so this function can not leak what it is not given. `JournalAsk`
    /// passes `recent` empty unless an experiment asks for it.
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

    /// The prompt again after `rejected` came back too close to a question already asked: the same
    /// prompt, then one sentence naming the rejected question and asking for another subject.
    public static func retryPrompt(_ prompt: String, rejected: String, language: JournalLanguage) -> String {
        switch language {
        case .en:
            return prompt + "\n\nThe question you just wrote, \"\(rejected)\", is too close to one that was already asked. Ask about something else from the facts."
        case .zhHans:
            return prompt + "\n\n你刚写的问题“\(rejected)”和已经问过的太接近了。请从上面的情况里换一件事来问。"
        }
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
        if let epic = signals.epic { lines.append(words.epic(epic)) }
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
        /// nothing and is not light, hard or ahead is just its text.
        func done(_ item: JournalSignals.Item) -> String {
            var notes: [String] = []
            if item.isLight { notes.append(zh ? "轻量版" : "light version") }
            if item.difficulty == .hard { notes.append(zh ? "困难" : "hard") }
            if item.isAhead { notes.append(zh ? "提前做的" : "done before its day") }
            if item.coins != 0 { notes.append(zh ? "+\(item.coins) 金币" : "+\(item.coins) coins") }
            guard !notes.isEmpty else { return item.subject.text }
            return zh ? item.subject.text + "（" + notes.joined(separator: "，") + "）"
                      : item.subject.text + " (" + notes.joined(separator: ", ") + ")"
        }

        /// The week's epic and where it stands.
        func epic(_ epic: JournalSignals.EpicStatus) -> String {
            let state: String
            switch epic.progress {
            case .doneToday(let spare) where spare > 0:
                state = zh ? "今天完成了，比截止早 \(spare) 天" : "Finished today, \(spare) \(days(spare)) before it was due"
            case .doneToday:
                state = zh ? "今天完成了，正好是最后一天" : "Finished today, on its last day"
            case .doneEarlier:
                state = zh ? "这周早些时候已经完成了" : "Already finished earlier this week"
            case .open(let left) where left > 0:
                state = zh ? "还没完成，还剩 \(left) 天" : "Not done yet, \(left) \(days(left)) left"
            case .open:
                state = zh ? "还没完成，今天是最后一天" : "Not done yet, and today is its last day"
            }
            return zh ? "本周的 Epic：\(epic.text)。\(state)。" : "This week's epic: \(epic.text). \(state)."
        }

        private func days(_ n: Int) -> String { n == 1 ? "day" : "days" }

        func list(_ label: String, _ items: [String], none: String? = nil) -> String {
            let colon = zh ? "：" : ": "
            let separator = zh ? "；" : "; "
            let end = zh ? "。" : "."
            return label + colon + (items.isEmpty ? (none ?? "") : items.joined(separator: separator)) + end
        }
    }
}
