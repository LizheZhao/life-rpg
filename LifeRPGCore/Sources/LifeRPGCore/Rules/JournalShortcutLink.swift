import Foundation

/// The links between the app and the user's own Shortcut. The Shortcut reads the day's text from
/// the app's App Intent, so no journal text is ever put in a URL: the run link carries the
/// shortcut's name and the three return links, and nothing else.
public enum JournalShortcutLink {
    public static let scheme = "liferpg"

    /// How a run came back. Each is a page the app registers for `liferpg://`.
    public enum Outcome: String, Sendable {
        case saved = "journal-saved"
        case cancelled = "journal-cancelled"
        case failed = "journal-failed"
    }

    /// Nil for a blank name: with no shortcut set there is nothing to run.
    public static func runURL(shortcutName: String) -> URL? {
        let name = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let encoded = name.addingPercentEncoding(withAllowedCharacters: unreserved)
        else { return nil }
        let link = { (outcome: Outcome) in "\(scheme)://\(outcome.rawValue)" }
        return URL(string: "shortcuts://x-callback-url/run-shortcut?name=\(encoded)"
                   + "&x-success=\(link(.saved))&x-cancel=\(link(.cancelled))&x-error=\(link(.failed))")
    }

    public static func outcome(of url: URL) -> Outcome? {
        guard url.scheme == scheme, let host = url.host else { return nil }
        return Outcome(rawValue: host)
    }

    /// Everything but the RFC 3986 unreserved characters is escaped, so `&` and `=` in a name can
    /// not start another parameter.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
