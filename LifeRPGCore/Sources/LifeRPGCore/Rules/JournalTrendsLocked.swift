import Foundation

extension JournalTrends {
    /// What the Trends page shows until a week of nights has been written. The wording is the
    /// design's and lives here so the page and any test read the same strings.
    public enum Locked {
        public struct Progress: Equatable, Sendable {
            public let written: Int
            public let of: Int

            /// "3 of 7 nights written".
            public var text: String { "\(written) of \(of) nights written" }
        }

        public struct Preview: Equatable, Sendable {
            public let title: String
            public let subtitle: String
        }

        /// Only asked while the page is locked, so `nightsWritten` is below `Writing.unlockNights`.
        public static func progress(nightsWritten: Int) -> Progress {
            Progress(written: nightsWritten, of: Writing.unlockNights)
        }

        public static let explanation = "Unlocks after 7 days of writing. Short entries count."

        /// What will appear once unlocked, in the order the page lists them.
        public static let previews: [Preview] = [
            Preview(title: "Words that defined the month", subtitle: "Filtered so \"today\" and \"feel\" never win"),
            Preview(title: "Favorite quests", subtitle: "Done most, rated best"),
            Preview(title: "Low energy days vs. what got done", subtitle: "Are the light versions working"),
            Preview(title: "Writing streak and usual hour", subtitle: "How steady the habit is"),
        ]
    }
}
