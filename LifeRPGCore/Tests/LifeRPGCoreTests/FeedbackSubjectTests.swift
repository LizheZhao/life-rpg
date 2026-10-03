import Foundation
import Testing
@testable import LifeRPGCore

/// What a card on the today page can be rated and noted *as*: the library row it came from.
/// A card with no such row (a custom task, a micro-action group) has nothing to file feedback under.
struct FeedbackSubjectTests {
    @Test func aDrawnQuestIsFiledUnderItsTemplate() throws {
        let q = DailyQuest()
        q.templateID = UUID()
        q.textSnapshot = "Compliment a stranger"
        let subject = try #require(Feedback.subject(of: q))
        #expect(subject.target == .quest)
        #expect(subject.id == q.templateID)
        #expect(subject.text == "Compliment a stranger")
        #expect(subject.instanceID == q.id)           // the one completion it can be linked to
    }

    @Test func aMicroGroupHasNoSingleTemplate() {
        let q = DailyQuest()
        q.templateID = UUID()
        q.trivialGroup = ["a", "b", "c"]
        #expect(Feedback.subject(of: q) == nil)
    }

    @Test func aQuestWithoutATemplateHasNoSubject() {
        #expect(Feedback.subject(of: DailyQuest()) == nil)
    }

    @Test func aRoutineIsFiledUnderItsRoutine() throws {
        let o = RoutineOccurrence()
        o.routineID = UUID()
        o.textSnapshot = "Take out the trash"
        let subject = try #require(Feedback.subject(of: o))
        #expect(subject.target == .routine)
        #expect(subject.id == o.routineID)
        #expect(subject.text == "Take out the trash")
        #expect(subject.instanceID == o.id)
    }

    /// Picked from the library through "+", it is still that routine (`Schedule.doneThisWeek` counts it so).
    @Test func anAdHocPickedFromTheLibraryIsFiledUnderTheRoutineItCameFrom() throws {
        let o = RoutineOccurrence()
        o.adHocSourceRoutineID = UUID()
        o.textSnapshot = "Review bills/statements"
        let subject = try #require(Feedback.subject(of: o))
        #expect(subject.id == o.adHocSourceRoutineID)
    }

    @Test func aCustomTaskHasNothingToFileUnder() {
        let o = RoutineOccurrence()
        o.textSnapshot = "Watch a movie"
        #expect(Feedback.subject(of: o) == nil)
    }

    @Test func aLightVersionIsNotedUnderItsOwnWording() throws {
        let o = RoutineOccurrence()
        o.routineID = UUID()
        o.textSnapshot = "Run 5k"
        o.degradedTextSnapshot = "Walk, 30 minutes"
        o.usedDegraded = true
        #expect(try #require(Feedback.subject(of: o)).text == "Walk, 30 minutes")
    }
}
