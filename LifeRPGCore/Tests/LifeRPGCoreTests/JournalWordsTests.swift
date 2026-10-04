import Testing
@testable import LifeRPGCore

struct JournalWordsTests {
    @Test func emptyAndBlankTextIsNoWords() {
        #expect(JournalWords.count("") == 0)
        #expect(JournalWords.count(" \n\t ") == 0)
    }

    @Test func englishWordsAreRunsOfLettersAndDigits() {
        #expect(JournalWords.count("I walked home in the rain") == 6)
        #expect(JournalWords.count("  two   spaces,\nand a newline ") == 5)
        #expect(JournalWords.count("3 miles at 5pm") == 4)
    }

    @Test func internalApostrophesAndHyphensDoNotSplitAWord() {
        #expect(JournalWords.count("don't") == 1)
        #expect(JournalWords.count("it\u{2019}s a well-known thing") == 4)
        #expect(JournalWords.count("mother-in-law") == 1)
    }

    @Test func aLeadingOrTrailingConnectorOrASpacedHyphenIsPunctuation() {
        #expect(JournalWords.count("'quoted'") == 1)
        #expect(JournalWords.count("rain - then sun") == 3)
        #expect(JournalWords.count("well- known") == 2)
        #expect(JournalWords.count("-- --") == 0)
    }

    @Test func otherPunctuationSplitsAndCountsForNothing() {
        #expect(JournalWords.count("3.5 km, (really!)") == 4)
        #expect(JournalWords.count("...!?") == 0)
        #expect(JournalWords.count("a/b") == 2)
    }

    @Test func eachChineseCharacterIsOneWord() {
        #expect(JournalWords.count("今天走路回家") == 6)
        #expect(JournalWords.count("今天，天气很好。") == 6)
    }

    @Test func kanaAndHangulCountPerCharacter() {
        #expect(JournalWords.count("ありがとう") == 5)
        #expect(JournalWords.count("カタカナ") == 4)
        #expect(JournalWords.count("감사") == 2)
    }

    /// 今 and 天 are two, then I, walked, 3 and miles are four more.
    @Test func mixedTextAddsTheTwoRules() {
        #expect(JournalWords.count("今天 I walked 3 miles") == 6)
        #expect(JournalWords.count("今天I walked") == 4)
        #expect(JournalWords.count("走了3公里") == 5)
    }

    @Test func accentsAndEmojiBehave() {
        #expect(JournalWords.count("café au lait") == 3)
        #expect(JournalWords.count("cafe\u{301} ok") == 2)
        #expect(JournalWords.count("so good \u{1F600}\u{1F600}") == 2)
    }
}
