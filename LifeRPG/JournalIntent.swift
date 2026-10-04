import AppIntents
import LifeRPGCore
import SwiftData

/// "Get Today's Journal Text", the action the user's Shortcut starts with: it hands the day's
/// composed journal to whatever comes next (Create Journal Entry). It runs in the app's process
/// without opening it, against the same container as the app (`AppStore`), and reads only.
struct GetTodaysJournalTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Today's Journal Text"
    static let description = IntentDescription(
        "Returns what you wrote in today's journal, with each question above your answer. Empty when nothing was answered.")
    static let openAppWhenRun = false

    enum Failure: Error, CustomLocalizedStringResourceConvertible {
        case storeUnavailable

        var localizedStringResource: LocalizedStringResource {
            "LifeRPG could not open its data, so there is no journal to read."
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let container = try? AppStore.opened.get() else { throw Failure.storeUnavailable }
        let turns = try JournalService.turns(on: Date().dayKey, in: container.mainContext)
        let language = JournalLanguage.resolve(preferred: Locale.preferredLanguages)
        return .result(value: JournalComposer.text(turns: turns, language: language))
    }
}
