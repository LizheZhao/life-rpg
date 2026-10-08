import Foundation
import LifeRPGCore

/// The model one tap of "Ask me something" talks to: the on-device one when the device has it,
/// nil otherwise, which `JournalAsk.resolve` answers with the next fixed prompt. On the simulator
/// the Debug page can force a result instead, so each path can be driven without a model.
enum JournalAskWording {
    nonisolated static func current(language: JournalLanguage) -> (any JournalWording)? {
        #if targetEnvironment(simulator)
        if let forced = JournalAskForce.current { return forced }
        #endif
        return JournalWordingProvider.current(language: language)
    }
}

/// What became of the model on the last tap of "Ask me something", for the Debug page: the editor
/// shows the same fallback toast whether there was no model, it timed out, it threw, or Core
/// rejected what it wrote.
enum JournalAskDebug {
    static let lastKey = "journalAskLastDiagnosis"
    private static let errorKey = "journalAskLastError"

    /// The model threw; `record` adds this to a `noAnswer` diagnosis.
    nonisolated static func noteError(_ error: Error) {
        UserDefaults.standard.set(String(describing: error), forKey: errorKey)
    }

    nonisolated static func record(_ diagnosis: JournalAskDiagnosis) {
        let defaults = UserDefaults.standard
        var line = diagnosis.summary
        if diagnosis == .noAnswer, let error = defaults.string(forKey: errorKey) {
            line += ": " + error
        }
        defaults.removeObject(forKey: errorKey)
        let time = Date().formatted(date: .abbreviated, time: .shortened)
        defaults.set(time + " · " + line, forKey: lastKey)
    }
}

#if targetEnvironment(simulator)
/// What the Debug page forces the model to do. `real` is no override.
enum JournalAskForce: String, CaseIterable {
    case real, question, timeout, error, garbage

    static let key = "debugJournalAsk"

    static var options: [(String, String)] { allCases.map { ($0.rawValue.capitalized, $0.rawValue) } }

    nonisolated static var current: (any JournalWording)? {
        let force = JournalAskForce(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .real
        return force == .real ? nil : ForcedWording(force: force)
    }
}

/// A canned model. `question` answers with the first line below the entry does not hold yet, read
/// off the prompt (which lists the questions already there), so repeated taps give distinct
/// questions and can reach the cap.
private struct ForcedWording: JournalWording {
    let force: JournalAskForce

    static let questions = [
        "What made the walk feel easier than you expected?",
        "Which part of today are you quietly glad about?",
        "What small thing went better than it looked?",
        "Where did you feel most like yourself today?",
        "What did you do first when the day felt heavy?",
        "What did your body ask for this afternoon?",
        "Which moment today would you like to keep?",
    ]

    func word(instructions: String, prompt: String) async -> String? {
        switch force {
        case .real, .error:
            return nil
        case .question:
            return Self.questions.first { !prompt.contains($0) } ?? Self.questions[0]
        case .timeout:
            try? await Task.sleep(for: .seconds(60))
            return nil
        case .garbage:
            return "Absolutely, here you go! Be kinder to yourself"
        }
    }
}
#endif
