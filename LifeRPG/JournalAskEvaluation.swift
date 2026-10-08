#if targetEnvironment(simulator)
import Foundation
import LifeRPGCore

/// Runs "Ask me something" against the real on-device model over a fixed set of made-up days and
/// writes what came back, for a person to read. Each sample is one model attempt on the path the
/// editor uses (`JournalAsk.request`, the model, `JournalAsk.check`), without the retry, so the
/// report shows first-attempt behaviour. Each scenario runs with the prompt listing the last
/// entries' questions and without it. Nothing is stored and nothing is judged here.
enum JournalAskEvaluation {
    static let samplesPerVariant = 4

    private static let dayKey = "2026-09-18"

    private struct Scenario {
        let id: String
        let language: JournalLanguage
        let signals: JournalSignals
        let document: JournalDocument
        let previousQuestions: [String]

        init(_ id: String, _ language: JournalLanguage = .en, signals: JournalSignals,
             document: JournalDocument = JournalDocument(), previous: [String] = []) {
            self.id = id
            self.language = language
            self.signals = signals
            self.document = document
            self.previousQuestions = previous
        }
    }

    private struct Sample: Codable {
        var scenario: String
        var language: String
        var variant: String
        var index: Int
        var facts: [String]
        var prompt: String
        /// answered, noAnswer, error, timedOut or noModel.
        var outcome: String
        var output: String?
        var error: String?
        var latencyMs: Int
        /// For an answer: accepted, or the rejection's name. "-" when there was no answer.
        var check: String
        var closestAvoided: String?
        var similarity: Double?

        /// The column of the summary table this sample counts in.
        var category: String { outcome == "answered" ? check : outcome }
    }

    private struct Reply: Sendable {
        let text: String?
    }

    // MARK: running

    /// The line to show when done. `progress` hears a line after each sample.
    static func run(progress: (String) -> Void) async -> String {
        guard JournalWordingProvider.current(language: .en) != nil else {
            return "Nothing run: the model is unavailable (\(JournalWordingProvider.status(language: .en)))."
        }
        let scenarios = makeScenarios()
        let variants = [("notListed", false), ("listed", true)]
        let total = scenarios.count * variants.count * samplesPerVariant
        var samples: [Sample] = []
        var warmed: Set<JournalLanguage> = []
        for scenario in scenarios {
            let wording = JournalWordingProvider.current(language: scenario.language)
            if let wording, warmed.insert(scenario.language).inserted { wording.prewarm() }
            let shown = facts(of: scenario)
            for index in 1...samplesPerVariant {
                for (variant, listsRecent) in variants {
                    let asked = JournalAsk.request(
                        language: scenario.language, signals: scenario.signals, document: scenario.document,
                        previousQuestions: scenario.previousQuestions, includeWriting: true,
                        listsRecentQuestions: listsRecent)
                    var sample = Sample(scenario: scenario.id, language: scenario.language.rawValue,
                                        variant: variant, index: index, facts: shown, prompt: asked.prompt,
                                        outcome: "noModel", latencyMs: 0, check: "-")
                    if let wording { await ask(wording, asked, into: &sample) }
                    samples.append(sample)
                    progress("\(samples.count) of \(total): \(scenario.id) \(variant) #\(index)")
                }
            }
        }
        return (try? write(samples, total: total)) ?? "The run finished but the report could not be written."
    }

    private static func ask(_ wording: any JournalWording, _ asked: JournalAskRequest, into sample: inout Sample) async {
        _ = JournalAskDebug.takeError()
        let started = ContinuousClock.now
        let reply = await JournalConversation.raced(JournalAsk.timeout) {
            Reply(text: await wording.word(instructions: asked.instructions, prompt: asked.prompt))
        }
        let elapsed = ContinuousClock.now - started
        sample.latencyMs = Int(elapsed.components.seconds) * 1000
            + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        guard let reply else {
            sample.outcome = "timedOut"
            return
        }
        if let error = JournalAskDebug.takeError() {
            sample.outcome = "error"
            sample.error = error
            return
        }
        guard let raw = reply.text else {
            sample.outcome = "noAnswer"
            return
        }
        sample.outcome = "answered"
        sample.output = raw
        switch JournalAsk.check(raw, request: asked) {
        case .success:
            sample.check = "accepted"
        case .failure(let reason):
            sample.check = reason.rawValue
            if reason == .notFresh, let nearest = JournalAsk.nearestAvoided(raw, request: asked) {
                sample.closestAvoided = nearest.question
                sample.similarity = nearest.similarity
            }
        }
    }

    // MARK: the days

    private static func at(_ day: String, hour: Int) -> Date {
        DayKey.date(day)!.addingTimeInterval(Double(hour) * 3600)
    }

    private static func quest(_ text: String, _ slot: Difficulty, done: Bool = true, hour: Int = 10) -> DailyQuest {
        let q = DailyQuest()
        q.dayKey = dayKey
        q.textSnapshot = text
        q.slot = slot
        if done {
            q.points = slot == .hard ? 40 : slot == .medium ? 20 : 10
            q.completedAt = at(dayKey, hour: hour)
        }
        return q
    }

    private static func routineDone(_ text: String, due: String = dayKey) -> RoutineOccurrence {
        let o = RoutineOccurrence()
        o.textSnapshot = text
        o.dueDayKey = due
        o.completedDayKey = dayKey
        o.completedAt = at(dayKey, hour: 11)
        o.awardedPoints = 15
        return o
    }

    /// A routine still open `daysAgo` days after its day, which the signals read as given up on.
    private static func routineSkipped(_ text: String, daysAgo: Int = 1) -> RoutineOccurrence {
        let o = RoutineOccurrence()
        o.textSnapshot = text
        o.dueDayKey = DayKey.adding(-daysAgo, to: dayKey)!
        return o
    }

    private static func signals(tier: Tier = .normal, quests: [DailyQuest] = [],
                                occurrences: [RoutineOccurrence] = [], ratings: [QuestRating] = [],
                                epic: DailyQuest? = nil) -> JournalSignals {
        let context = DailyContext()
        context.dayKey = dayKey
        context.tier = tier
        return JournalSignals(dayKey: dayKey, quests: quests, occurrences: occurrences, context: context,
                              ratings: ratings, epic: epic)
    }

    private static func quietDay(_ language: JournalLanguage) -> JournalSignals {
        let zh = language == .zhHans
        return signals(quests: [quest(zh ? "散步 20 分钟" : "Take a 20 minute walk", .easy, hour: 8),
                                quest(zh ? "整理书桌" : "Tidy the desk", .easy, hour: 12),
                                quest(zh ? "读 20 页书" : "Read 20 pages", .medium, hour: 16)])
    }

    private static func lowDay(_ language: JournalLanguage) -> JournalSignals {
        let zh = language == .zhHans
        return signals(tier: .low, quests: [quest(zh ? "伸展 10 分钟" : "Stretch for 10 minutes", .easy)],
                       occurrences: [routineSkipped(zh ? "练钢琴" : "Piano practice")])
    }

    private static func makeScenarios() -> [Scenario] {
        let epic = DailyQuest()
        epic.dayKey = "2026-09-14"
        epic.textSnapshot = "Write the quarterly report"
        epic.slot = .epic
        epic.points = 100
        epic.completedAt = at(dayKey, hour: 15)

        let cooked = quest("Cook a new recipe", .medium)
        let rating = QuestRating()
        rating.questID = cooked.id
        rating.rating = 2
        rating.dayKey = dayKey
        rating.timestamp = at(dayKey, hour: 19)

        let written = JournalDocument(blocks: [
            .text(id: UUID(), text: "Felt scattered today, too many tabs open and no real break."),
            .prompt(id: UUID(), question: "What are you grateful for today?",
                    answer: "Lunch with Mei. It was the first slow meal this week.",
                    source: .fixed, fixedKey: .gratefulFor),
        ])
        let copies = ["What was the best moment of your day?", "What did you think of the new album?",
                      "What was it like when you made a cup of tea?"]
        let copiesZh = ["今天最美好的一刻是什么？", "你觉得新专辑怎么样？", "泡一杯茶的时候是什么感觉？"]

        return [
            Scenario("01-quiet-day", signals: quietDay(.en)),
            Scenario("02-hard-quest", signals: signals(quests: [quest("Run 5 km", .hard)])),
            Scenario("03-low-energy-skipped-routine", signals: lowDay(.en)),
            Scenario("04-epic-early", signals: signals(epic: epic)),
            Scenario("05-routine-a-day-ahead",
                     signals: signals(occurrences: [routineDone("Clean the kitchen", due: DayKey.adding(1, to: dayKey)!)])),
            Scenario("06-four-open-nothing-done",
                     signals: signals(quests: [quest("Take a 20 minute walk", .easy, done: false),
                                               quest("Tidy the desk", .easy, done: false),
                                               quest("Read 20 pages", .medium, done: false),
                                               quest("Call a friend", .medium, done: false)])),
            Scenario("07-quest-rated-high", signals: signals(quests: [cooked], ratings: [rating])),
            Scenario("08-entry-already-written", signals: quietDay(.en), document: written),
            Scenario("09-previous-questions", signals: quietDay(.en), previous: copies),
            Scenario("10-very-low-two-skipped",
                     signals: signals(tier: .veryLow,
                                      occurrences: [routineSkipped("Piano practice"),
                                                    routineSkipped("Water the plants", daysAgo: 2)])),
            Scenario("01-quiet-day-zh", .zhHans, signals: quietDay(.zhHans)),
            Scenario("03-low-energy-skipped-routine-zh", .zhHans, signals: lowDay(.zhHans)),
            Scenario("09-previous-questions-zh", .zhHans, signals: quietDay(.zhHans), previous: copiesZh),
        ]
    }

    /// The scenario as a person would say it, read off the same rows the prompt is built from.
    private static func facts(of scenario: Scenario) -> [String] {
        let signals = scenario.signals
        var lines = ["energy tier: \(signals.tier.rawValue)"]
        let done = signals.completed.map { item -> String in
            var notes = [item.difficulty?.rawValue, item.isAhead ? "done before its day" : nil,
                         item.rating.map { "rated \($0 > 0 ? "+" : "")\($0)" }].compactMap { $0 }
            if item.isLight { notes.append("light version") }
            return item.subject.text + (notes.isEmpty ? "" : " (" + notes.joined(separator: ", ") + ")")
        }
        lines.append("done: " + (done.isEmpty ? "nothing" : done.joined(separator: "; ")))
        if !signals.skipped.isEmpty { lines.append("skipped: " + signals.skipped.map(\.text).joined(separator: "; ")) }
        if !signals.leftOpen.isEmpty { lines.append("open: " + signals.leftOpen.map(\.text).joined(separator: "; ")) }
        if let epic = signals.epic {
            switch epic.progress {
            case .doneToday(let spare): lines.append("epic: \(epic.text), finished with \(spare) days to spare")
            case .doneEarlier: lines.append("epic: \(epic.text), finished earlier this week")
            case .open(let left): lines.append("epic: \(epic.text), not done, \(left) days left")
            }
        }
        lines.append("entry: " + (JournalPromptBuilder.writing(of: scenario.document) ?? "empty"))
        if !scenario.previousQuestions.isEmpty {
            lines.append("previous entries asked: " + scenario.previousQuestions.joined(separator: " | "))
        }
        return lines
    }

    // MARK: the report

    private static func write(_ samples: [Sample], total: Int) throws -> String {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let name = "ask-eval-" + stamp.string(from: Date())
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(samples).write(to: documents.appendingPathComponent(name + ".json"))
        try markdown(samples, title: name).write(to: documents.appendingPathComponent(name + ".md"),
                                                 atomically: true, encoding: .utf8)
        return "Wrote \(total) samples to \(name).json and \(name).md in the app's Documents directory."
    }

    private static func markdown(_ samples: [Sample], title: String) -> String {
        var out = ["# \(title)", "",
                   "\(samplesPerVariant) samples per scenario and variant. One model attempt per sample, no retry, "
                   + "the entry's writing sent. `notListed` is the prompt without the last entries' questions, "
                   + "`listed` the old prompt with them. Scenarios with no previous entries get the same prompt in both.", ""]
        var seen: [String] = []
        for sample in samples {
            if !seen.contains(sample.scenario) {
                seen.append(sample.scenario)
                out += ["## \(sample.scenario) (\(sample.language))", ""] + sample.facts.map { "- " + $0 } + [""]
            }
            out.append("### \(sample.variant) #\(sample.index): \(sample.category), \(sample.latencyMs) ms")
            out += ["", "Prompt:", "```", sample.prompt, "```", ""]
            out.append("Output: " + (sample.output.map { "`" + $0.replacingOccurrences(of: "\n", with: "\\n") + "`" }
                                       ?? sample.error ?? "none"))
            if let closest = sample.closestAvoided, let similarity = sample.similarity {
                out.append("Closest avoided question: \"\(closest)\" at \(String(format: "%.2f", similarity))")
            }
            out.append("")
        }
        let columns = ["accepted"] + JournalAskRejection.allCases.map(\.rawValue)
            + ["noAnswer", "error", "timedOut", "noModel"]
        out += ["## Totals", "", "| variant | " + columns.joined(separator: " | ") + " |",
                "|---|" + columns.map { _ in "---|" }.joined()]
        for variant in ["notListed", "listed"] {
            let mine = samples.filter { $0.variant == variant }
            out.append("| \(variant) | " + columns.map { column in "\(mine.filter { $0.category == column }.count)" }
                .joined(separator: " | ") + " |")
        }
        return out.joined(separator: "\n") + "\n"
    }
}
#endif
