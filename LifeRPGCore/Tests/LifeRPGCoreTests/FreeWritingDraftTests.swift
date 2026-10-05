import Foundation
import Testing
@testable import LifeRPGCore

struct FreeWritingDraftTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aDraftStartsEqualToTheStoreAndHasNothingToSave() {
        let draft = FreeWritingDraft(text: "Already here.", writingSeconds: 90)
        #expect(!draft.hasUnsavedChanges)
        #expect(draft.wordCount == 2)
        #expect(draft.writingSeconds == 90)
    }

    @Test func aChangeNeedsASaveUntilItIsMarkedSaved() {
        var draft = FreeWritingDraft()
        draft.edit(to: "Hello", at: t0)
        #expect(draft.hasUnsavedChanges)
        draft.markSaved()
        #expect(!draft.hasUnsavedChanges)
        draft.edit(to: "Hello there", at: t0.addingTimeInterval(2))
        #expect(draft.hasUnsavedChanges)
    }

    @Test func theSameTextIsNotAKeystroke() {
        var draft = FreeWritingDraft(text: "Hello", writingSeconds: 5)
        draft.edit(to: "Hello", at: t0)
        draft.edit(to: "Hello!", at: t0.addingTimeInterval(4))
        // The ignored call did not become the clock's first keystroke, so the gap is not measured
        // from it: the first real keystroke adds nothing.
        #expect(draft.writingSeconds == 5)
    }

    @Test func writingTimeIsTheGapsBetweenKeystrokesCappedAtThirty() {
        var draft = FreeWritingDraft()
        draft.edit(to: "a", at: t0)
        draft.edit(to: "ab", at: t0.addingTimeInterval(10))
        #expect(draft.writingSeconds == 10)
        draft.edit(to: "abc", at: t0.addingTimeInterval(10 + 600))
        #expect(draft.writingSeconds == 40)
    }

    @Test func aResumedPageDoesNotCountTheTimeAwayAndKeepsTheStoredTotal() {
        var draft = FreeWritingDraft(text: "Earlier.", writingSeconds: 120)
        draft.edit(to: "Earlier. More", at: t0)
        #expect(draft.writingSeconds == 120)
    }

    @Test func aStarterIsInsertedAsAParagraphAndCountsAsTyping() {
        var draft = FreeWritingDraft()
        draft.edit(to: "First paragraph.", at: t0)
        let starter = JournalStarter(id: "starter.grateful", text: "Grateful for")
        draft.insert(starter, at: t0.addingTimeInterval(10))
        #expect(draft.text == "First paragraph.\n\nGrateful for ")
        // The tap is a keystroke: the gap since the last one is writing time.
        #expect(draft.writingSeconds == 10)
    }
}
