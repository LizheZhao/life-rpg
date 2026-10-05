import Foundation

/// The four fixed prompts on the chip bar above the keyboard. A prompt block made from one carries
/// its key, which is how a chip knows it is already in the entry and how Trends finds the
/// "Grateful for" answers.
public enum JournalFixedKey: String, Codable, CaseIterable, Sendable {
    case favoriteMoment, gratefulFor, lowEnergyFeltLike, tomorrow

    /// The order the chips are offered when the model could not be reached (`nextFallback`).
    public static let fallbackOrder: [JournalFixedKey] = [.favoriteMoment, .gratefulFor, .tomorrow, .lowEnergyFeltLike]

    /// The first of `fallbackOrder` the document does not hold yet; nil when it holds all four.
    public static func nextFallback(missingFrom document: JournalDocument) -> JournalFixedKey? {
        fallbackOrder.first { !document.containsFixedKey($0) }
    }

    /// The label on the chip.
    public func chipLabel(language: JournalLanguage) -> String { wording(language).chip }

    /// The question text inserted when the chip is tapped.
    public func question(language: JournalLanguage) -> String { wording(language).question }

    private struct Wording {
        let chip: String
        let question: String
    }

    /// The one table of chip and question wording, English then Simplified Chinese per key.
    private func wording(_ language: JournalLanguage) -> Wording {
        let (en, zh): (Wording, Wording)
        switch self {
        case .favoriteMoment:
            en = Wording(chip: "Favorite moment", question: "What was your favorite moment today?")
            zh = Wording(chip: "最喜欢的瞬间", question: "今天最喜欢的瞬间是什么？")
        case .gratefulFor:
            en = Wording(chip: "Grateful for", question: "What are you grateful for today?")
            zh = Wording(chip: "感恩", question: "今天你感恩什么？")
        case .lowEnergyFeltLike:
            en = Wording(chip: "Low energy felt like", question: "What did the low energy feel like today?")
            zh = Wording(chip: "低能量的感觉", question: "今天低能量是什么感觉？")
        case .tomorrow:
            en = Wording(chip: "Tomorrow", question: "What do you want to carry into tomorrow?")
            zh = Wording(chip: "明天", question: "你想把什么带进明天？")
        }
        return language == .zhHans ? zh : en
    }
}
