import Foundation

/// An error whose `description` is written for the person using the app: the rule's own reason,
/// e.g. "already completed". Anything else (a SwiftData save, a file read) is not, and must never
/// reach a banner as `"\(error)"`.
public protocol UserFacingError: Error, CustomStringConvertible {}

extension Purchase.Blocked: UserFacingError {}
extension AdHoc.Failure: UserFacingError {}
extension Epic.Failure: UserFacingError {}
extension Completion.Failure: UserFacingError {}
extension LibraryEdit.Failure: UserFacingError {}
extension LibrarySave.Failure: UserFacingError {}
extension Degrade.Failure: UserFacingError {}
extension JSONImport.Failure: UserFacingError {}
extension StarterLibraryError: UserFacingError {}

/// What a banner says when an action throws.
public enum ErrorText {
    public static let fallback = "That didn't go through. Try again."

    /// A rule's reason as a sentence; `otherwise` for an error no rule wrote.
    public static func message(_ error: any Error, otherwise: String = fallback) -> String {
        guard let error = error as? any UserFacingError else { return otherwise }
        return sentence(error.description)
    }

    private static func sentence(_ text: String) -> String {
        guard let first = text.first else { return fallback }
        let capped = first.uppercased() + text.dropFirst()
        return capped.hasSuffix(".") || capped.hasSuffix("!") || capped.hasSuffix("?") ? capped : capped + "."
    }
}
