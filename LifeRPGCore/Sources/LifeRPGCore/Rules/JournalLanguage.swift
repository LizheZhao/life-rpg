import Foundation

/// The two languages the journal speaks. It follows the system language, and anything that is not
/// Simplified Chinese reads as English, Traditional Chinese included: there is no zh-Hant pool.
public enum JournalLanguage: String, Codable, CaseIterable, Sendable {
    case en
    case zhHans = "zh-Hans"

    /// The first preferred language is the system language, and it alone decides. `preferred` is
    /// `Locale.preferredLanguages`, which carries region and script suffixes (`zh-Hans-CN`).
    public static func resolve(preferred: [String]) -> JournalLanguage {
        preferred.first.map(isSimplifiedChinese) == true ? .zhHans : .en
    }

    private static func isSimplifiedChinese(_ identifier: String) -> Bool {
        let id = identifier.replacingOccurrences(of: "_", with: "-")
        return id.hasPrefix("zh-Hans") || ["zh", "zh-CN", "zh-SG"].contains(id)
    }
}
