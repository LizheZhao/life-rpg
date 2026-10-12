import Foundation
import Testing
@testable import LifeRPGCore

struct JournalTrendsLockedTests {
    typealias Locked = JournalTrends.Locked

    @Test func progressIsNightsWrittenOutOfSeven() {
        #expect(Locked.progress(nightsWritten: 3) == Locked.Progress(written: 3, of: 7))
        #expect(Locked.progress(nightsWritten: 0) == Locked.Progress(written: 0, of: 7))
    }

    @Test func theProgressLineReadsAsTheDesignHasIt() {
        #expect(Locked.progress(nightsWritten: 3).text == "3 of 7 nights written")
    }

    @Test func theLockedPageSaysWhyAndListsWhatUnlocks() {
        #expect(Locked.explanation == "Unlocks after 7 days of writing. Short entries count.")
        #expect(Locked.previews.map(\.title) == [
            "Words that defined the month",
            "Favorite quests",
            "Low energy days vs. what got done",
            "Writing streak and usual hour",
        ])
        #expect(Locked.previews.map(\.subtitle) == [
            "Filtered so \"today\" and \"feel\" never win",
            "Done most, rated best",
            "Are the light versions working",
            "How steady the habit is",
        ])
    }
}
