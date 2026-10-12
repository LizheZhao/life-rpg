import Foundation

/// A re-plan the user turned down with "Leave it". The foreground re-read would otherwise offer
/// the same change again every time the app comes forward, because nothing remembered the refusal.
///
/// What counts as the same change is the day and what it would turn into: the tier it moves to and
/// whether it is a recovery day. Another tier the same day, or any change on a later day, is a new
/// question and is offered. Only today's refusals are kept.
extension Replan {
    public struct Declined: Equatable, Hashable, Codable, Sendable {
        public var dayKey: String
        public var toTier: Tier
        public var toRecovery: Bool

        public init(_ change: Change) {
            dayKey = change.dayKey
            toTier = change.toTier
            toRecovery = change.toRecovery
        }
    }

    public static func shouldOffer(_ change: Change, declined: [Declined]) -> Bool {
        !declined.contains(Declined(change))
    }

    /// `declined` plus this refusal, without anything left over from another day.
    public static func remembering(_ change: Change, in declined: [Declined]) -> [Declined] {
        var kept = declined.filter { $0.dayKey == change.dayKey }
        let new = Declined(change)
        if !kept.contains(new) { kept.append(new) }
        return kept
    }

    public static func decodeDeclined(_ raw: String) -> [Declined] {
        (try? JSONDecoder().decode([Declined].self, from: Data(raw.utf8))) ?? []
    }

    public static func encodeDeclined(_ declined: [Declined]) -> String {
        (try? JSONEncoder().encode(declined)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
