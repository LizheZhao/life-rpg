import AppIntents
import LifeRPGCore
import SwiftData

/// "Get Journal Text to Send", the action the user's nightly Shortcut starts with. The automation
/// runs at the app's day boundary (05:00), when today is already the new day, so this reads the
/// day before it (`JournalSend.finishedDayKey`) and hands its journal to whatever comes next
/// (Create Journal Entry). It runs in the app's process without opening it, against the same
/// container as the app (`AppStore`). The only thing it writes is the sent log.
struct GetJournalTextToSendIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Journal Text to Send"
    static let description = IntentDescription(
        "Last night's journal, ready for Apple Journal. Empty if there's nothing to send.")
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
        return .result(value: try JournalHandOff.textToSend(now: Date(), in: container.mainContext))
    }
}
