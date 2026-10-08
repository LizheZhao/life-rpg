#if targetEnvironment(simulator)
import Foundation
import LifeRPGCore

/// Runs "Ask me something" over a fixed set of made-up days on the path the editor takes
/// (`JournalAsk.resolve` with the real on-device model, `JournalAsk.timeout` and `retryTimeout`)
/// and writes what came back, for a person to read. The real model is wrapped in a recorder, so
/// the report shows every call resolve made (one, or two when it asked again), Core's verdict on
/// each, and what the editor would have done with the tap. Nothing is stored and nothing is
/// judged here.
enum JournalAskEvaluation {
    static let samplesPerScenario = 4

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

    /// One call resolve made to the model.
    private struct Attempt: Codable {
        var prompt: String
        var output: String?
        var error: String?
        /// Nil when the call had not answered by the time resolve returned: it timed out.
        var latencyMs: Int?
        /// accepted, a `JournalAskRejection` name, or noAnswer, error, timedOut.
        var verdict: String
        var closestAvoided: String?
        var similarity: Double?
    }

    private struct Sample: Codable {
        var scenario: String
        var language: String
        var index: Int
        var facts: [String]
        var attempts: [Attempt]
        /// modelFirstTry, modelRetry, dayQuestion, chip, exhausted, safety or capped.
        var resultKind: String
        var resultText: String?
        var diagnosis: String

        var firstVerdict: String { attempts.first?.verdict ?? "noAttempt" }
    }

    /// The real model, remembering every call it is asked for.
    private nonisolated final class RecordingWording: JournalWording, @unchecked Sendable {
        struct Call {
            let prompt: String
            var output: String?
            var error: String?
            var latencyMs: Int?
        }

        private let inner: any JournalWording
        private let lock = NSLock()
        private var recorded: [Call] = []

        init(_ inner: any JournalWording) { self.inner = inner }

        var calls: [Call] { lock.withLock { recorded } }

        func prewarm() { inner.prewarm() }

        func word(instructions: String, prompt: String) async -> String? {
            _ = JournalAskDebug.takeError()
            let started = ContinuousClock.now
            let slot = lock.withLock { () -> Int in
                recorded.append(Call(prompt: prompt))
                return recorded.count - 1
            }
            let output = await inner.word(instructions: instructions, prompt: prompt)
            let elapsed = ContinuousClock.now - started
            let error = JournalAskDebug.takeError()
            lock.withLock {
                recorded[slot].output = output
                recorded[slot].error = error
                recorded[slot].latencyMs = Int(elapsed.components.seconds) * 1000
                    + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
            }
            return output
        }
    }

    /// The diagnosis `resolve` reports, once.
    private nonisolated final class Heard: @unchecked Sendable {
        private let lock = NSLock()
        private var value: JournalAskDiagnosis?
        func set(_ diagnosis: JournalAskDiagnosis) { lock.withLock { value = diagnosis } }
        var diagnosis: JournalAskDiagnosis? { lock.withLock { value } }
    }

    // MARK: running

    /// The line to show when done. `progress` hears a line after each sample.
    static func run(progress: (String) -> Void) async -> String {
        guard JournalWordingProvider.current(language: .en) != nil else {
            return "Nothing run: the model is unavailable (\(JournalWordingProvider.status(language: .en)))."
        }
        let scenarios = makeScenarios()
        let total = scenarios.count * samplesPerScenario
        var samples: [Sample] = []
        var warmed: Set<JournalLanguage> = []
        for scenario in scenarios {
            let real = JournalWordingProvider.current(language: scenario.language)
            if let real, JournalAsk.usesModel(for: scenario.language), warmed.insert(scenario.language).inserted {
                real.prewarm()
            }
            let shown = facts(of: scenario)
            for index in 1...samplesPerScenario {
                let recorder = real.map(RecordingWording.init)
                let heard = Heard()
                let result = await JournalAsk.resolve(
                    language: scenario.language, signals: scenario.signals, document: scenario.document,
                    previousQuestions: scenario.previousQuestions, includeWriting: true,
                    wording: recorder, timeout: JournalAsk.timeout, retryTimeout: JournalAsk.retryTimeout,
                    diagnose: { heard.set($0) })
                samples.append(sample(scenario, index: index, facts: shown, calls: recorder?.calls ?? [],
                                      result: result, diagnosis: heard.diagnosis))
                progress("\(samples.count) of \(total): \(scenario.id) #\(index)")
            }
        }
        return (try? write(samples, total: total)) ?? "The run finished but the report could not be written."
    }

    /// What one tap came to. The request is rebuilt exactly as `resolve` builds it, so `check` judges
    /// each raw answer against the same `avoiding` list and the same early fact.
    private static func sample(_ scenario: Scenario, index: Int, facts: [String], calls: [RecordingWording.Call],
                               result: JournalAskResult, diagnosis: JournalAskDiagnosis?) -> Sample {
        let asked = JournalAsk.request(
            language: scenario.language, signals: scenario.signals, document: scenario.document,
            previousQuestions: scenario.previousQuestions, includeWriting: true)
        let attempts = calls.map { call -> Attempt in
            var attempt = Attempt(prompt: call.prompt, output: call.output, error: call.error,
                                  latencyMs: call.latencyMs, verdict: "")
            guard let raw = call.output else {
                attempt.verdict = call.error != nil ? "error" : call.latencyMs == nil ? "timedOut" : "noAnswer"
                return attempt
            }
            switch JournalAsk.check(raw, request: asked) {
            case .success:
                attempt.verdict = "accepted"
            case .failure(let reason):
                attempt.verdict = reason.rawValue
                if reason == .notFresh, let nearest = JournalAsk.nearestAvoided(raw, request: asked) {
                    attempt.closestAvoided = nearest.question
                    attempt.similarity = nearest.similarity
                }
            }
            return attempt
        }
        let kind: String
        let text: String?
        switch result {
        case .question(let question):
            kind = attempts.count > 1 ? "modelRetry" : "modelFirstTry"
            text = question
        case .fromDay(let question, _):
            kind = "dayQuestion"
            text = question
        case .fallback(let key, _):
            kind = "chip"
            text = key.question(language: scenario.language)
        case .exhausted:
            kind = "exhausted"
            text = nil
        case .safety(let line):
            kind = "safety"
            text = line
        case .capped:
            kind = "capped"
            text = nil
        }
        return Sample(scenario: scenario.id, language: scenario.language.rawValue, index: index, facts: facts,
                      attempts: attempts, resultKind: kind, resultText: text,
                      diagnosis: diagnosis?.summary ?? "the model was not asked")
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
        let argued = JournalDocument(blocks: [
            .text(id: UUID(), text: "Argued with my sister on the phone this afternoon, then went for a long walk to cool off."),
        ])
        let writtenZh = JournalDocument(blocks: [
            .text(id: UUID(), text: "今天心很乱，开了太多标签页，也没怎么休息。"),
            .prompt(id: UUID(), question: "今天你感恩什么？",
                    answer: "和小梅吃了午饭，这周第一顿不赶时间的饭。",
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
            Scenario("11-entry-argument", signals: signals(), document: argued),
            Scenario("01-quiet-day-zh", .zhHans, signals: quietDay(.zhHans)),
            Scenario("03-low-energy-skipped-routine-zh", .zhHans, signals: lowDay(.zhHans)),
            Scenario("09-previous-questions-zh", .zhHans, signals: quietDay(.zhHans), previous: copiesZh),
            Scenario("12-entry-already-written-zh", .zhHans, signals: quietDay(.zhHans), document: writtenZh),
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

    private static let resultKinds = ["modelFirstTry", "modelRetry", "dayQuestion", "chip", "exhausted", "safety", "capped"]

    private static func markdown(_ samples: [Sample], title: String) -> String {
        var out = ["# \(title)", "",
                   "\(samplesPerScenario) samples per scenario. Each sample is one `JournalAsk.resolve` call as the editor makes it: "
                   + "the entry's writing sent, `JournalAsk.timeout` and `retryTimeout`, the real model recorded. "
                   + "The prompt lists neither the last entries' questions nor the tone anchors; "
                   + "Core still rejects an answer that copies one. A Chinese scenario shows no attempts when the model is off "
                   + "for the language (`JournalAsk.modelLanguages`).", ""]
        var seen: [String] = []
        for sample in samples {
            if !seen.contains(sample.scenario) {
                seen.append(sample.scenario)
                out += ["## \(sample.scenario) (\(sample.language))", ""] + sample.facts.map { "- " + $0 } + [""]
            }
            out.append("### #\(sample.index): \(sample.resultKind), \(sample.attempts.count) attempt(s)")
            out += ["", "Result: " + (sample.resultText.map { "`" + $0.replacingOccurrences(of: "\n", with: "\\n") + "`" } ?? "none"),
                    "Diagnosis: " + sample.diagnosis, ""]
            for (number, attempt) in sample.attempts.enumerated() {
                out.append("Attempt \(number + 1): \(attempt.verdict), "
                           + (attempt.latencyMs.map { "\($0) ms" } ?? "no answer in time"))
                out += ["", "Prompt:", "```", attempt.prompt, "```", ""]
                out.append("Output: " + (attempt.output.map { "`" + $0.replacingOccurrences(of: "\n", with: "\\n") + "`" }
                                           ?? attempt.error ?? "none"))
                if let closest = attempt.closestAvoided, let similarity = attempt.similarity {
                    out.append("Closest avoided question: \"\(closest)\" at \(String(format: "%.2f", similarity))")
                }
                out.append("")
            }
        }
        let verdicts = ["accepted"] + JournalAskRejection.allCases.map(\.rawValue)
            + ["noAnswer", "error", "timedOut", "noAttempt"]
        out += ["## Totals", "", "First-attempt verdict (noAttempt: the model was not called)", ""]
            + table(verdicts, samples) { $0.firstVerdict }
        out += ["", "Final result", ""] + table(resultKinds, samples) { $0.resultKind }
        return out.joined(separator: "\n") + "\n"
    }

    /// A table of counts with a row for English and one for Chinese.
    private static func table(_ columns: [String], _ samples: [Sample], by value: (Sample) -> String) -> [String] {
        let rows: [(label: String, language: JournalLanguage)] = [("en", .en), ("zh", .zhHans)]
        return ["| language | " + columns.joined(separator: " | ") + " |",
                "|---|" + columns.map { _ in "---|" }.joined()]
            + rows.map { row in
                let mine = samples.filter { $0.language == row.language.rawValue }
                return "| \(row.label) | " + columns.map { column in "\(mine.filter { value($0) == column }.count)" }
                    .joined(separator: " | ") + " |"
            }
    }
}
#endif
