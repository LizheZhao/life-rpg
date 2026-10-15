import Foundation
import Testing
@testable import LifeRPGCore

/// What a banner says when an action throws: the rule's own reason as a sentence, never a type
/// name or a raw dayKey, and one plain line for anything the rules didn't write.
struct ErrorTextTests {
    @Test func aRuleFragmentBecomesASentence() {
        #expect(ErrorText.message(Completion.Failure.alreadyCompleted) == "Already completed.")
        #expect(ErrorText.message(LibraryEdit.Failure.emptyText) == "It needs a name.")
    }

    @Test func aReasonThatIsAlreadyASentenceIsLeftAlone() {
        #expect(ErrorText.message(Purchase.Blocked.inDebt(balance: -5)) == "In debt (-5). Earn it back first.")
        #expect(ErrorText.message(JSONImport.Failure.unreadable) == "This file isn't a Life RPG export.")
    }

    @Test func datesAreWrittenOutNotPrintedAsKeys() {
        #expect(ErrorText.message(Epic.Failure.expired(lastDayKey: "2026-10-11")) == "Ran out on Sun Oct 11.")
        #expect(ErrorText.message(Completion.Failure.outsideRound(dueDayKey: "2026-10-12", dayKey: "2026-10-20"))
                == "Due Mon Oct 12, so it can't be done on Tue Oct 20.")
    }

    @Test func difficultyIsAWordNotALetter() {
        #expect(ErrorText.message(AdHoc.Failure.noBasePoints) == "Pick easy, medium or hard.")
        #expect(ErrorText.message(LibrarySave.Failure.noDifficulty) == "Pick easy, medium or hard.")
        #expect(ErrorText.message(Completion.Failure.trivialGroupIncomplete(remaining: 2)) == "2 small tasks still to do.")
        #expect(ErrorText.message(Completion.Failure.trivialGroupIncomplete(remaining: 1)) == "1 small task still to do.")
    }

    @Test func aPriceSaysWhatYouHave() {
        #expect(ErrorText.message(Purchase.Blocked.tooExpensive(cost: 50, balance: 20)) == "Costs 50 coins, you have 20.")
    }

    @Test func anErrorTheRulesDidNotWriteGetsOnePlainLine() {
        struct Opaque: Error {}
        #expect(ErrorText.message(Opaque()) == "That didn't go through. Try again.")
        #expect(ErrorText.message(CocoaError(.fileWriteUnknown), otherwise: "Couldn't export the records.")
                == "Couldn't export the records.")
    }

    @Test func aSlotIsNamedInWords() {
        #expect(Difficulty.easy.word == "easy")
        #expect(Difficulty.hard.word == "hard")
        #expect(Difficulty.trivial.word == "trivial")
    }
}
