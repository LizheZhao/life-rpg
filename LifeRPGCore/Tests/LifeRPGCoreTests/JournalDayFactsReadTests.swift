import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

struct JournalDayFactsReadTests {
    private let friday = "2026-09-18"

    @Test func theFactsAreReadFromTheDaysRows() throws {
        let ctx = try Fixtures.context()
        let done = DailyQuest()
        done.dayKey = friday; done.textSnapshot = "Walk"; done.points = 10; done.completedAt = Date()
        ctx.insert(done)
        let open = DailyQuest()
        open.dayKey = friday; open.textSnapshot = "Read"
        ctx.insert(open)
        let tierDay = DailyContext()
        tierDay.dayKey = friday; tierDay.tier = .low
        ctx.insert(tierDay)
        try ctx.save()
        let facts = try JournalDayFacts.read(dayKey: friday, in: ctx)
        #expect(facts.completed == 1)
        #expect(facts.tierText == "low day")
        #expect(try JournalDayFacts.read(dayKey: "2026-01-01", in: ctx) == JournalDayFacts(completed: 0, tierText: nil))
    }
}
