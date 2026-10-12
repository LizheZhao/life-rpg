import Foundation

/// The name a person gives the app. It is kept on the phone (`UserDefaults`, not the store) and
/// only ever shown back to them, in the greeting. The backup carries it (schema 11).
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

    /// What a restore writes as the name: the backup's, but only onto a phone that has none. A name
    /// already here is the person's latest answer and is never overwritten. Nil means leave it.
    public static func restoredName(fromBackup backup: String?, local: String?) -> String? {
        guard cleanName(local) == nil else { return nil }
        return cleanName(backup)
    }
}
