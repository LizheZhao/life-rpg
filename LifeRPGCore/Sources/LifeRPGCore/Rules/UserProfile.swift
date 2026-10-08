import Foundation

/// The name a person gives the app. It is kept on the phone (not in the store or the backup) and
/// only ever shown back to them, in the greeting.
public enum UserProfile {
    public static let maxLength = 30

    /// What the name field becomes: whitespace and line breaks collapsed to single spaces, cut at
    /// `maxLength` characters (characters, so Chinese and emoji stay whole). Nothing left is no name.
    public static func cleanName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let words = raw.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return nil }
        let joined = words.joined(separator: " ")
        return String(joined.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
    }
}
