import Foundation
import Testing
@testable import LifeRPGCore

/// UIKit's cursor is in UTF-16 code units, the document's in `Character`s.
struct JournalCursorTests {
    @Test func plainAsciiIsTheSameNumber() {
        #expect(JournalCursor.characterOffset(forUTF16Offset: 3, in: "hello") == 3)
        #expect(JournalCursor.utf16Offset(forCharacterOffset: 3, in: "hello") == 3)
    }

    @Test func anEmojiIsTwoUnitsButOneCharacter() {
        // "a😀b": a=1 unit, 😀=2 units, b=1 unit.
        #expect(JournalCursor.characterOffset(forUTF16Offset: 3, in: "a😀b") == 2)
        #expect(JournalCursor.characterOffset(forUTF16Offset: 4, in: "a😀b") == 3)
        #expect(JournalCursor.utf16Offset(forCharacterOffset: 2, in: "a😀b") == 3)
    }

    @Test func aFlagAndAFamilyAreOneCharacterEach() {
        let text = "🇨🇳x👨‍👩‍👧y"
        #expect(text.count == 4)
        #expect(JournalCursor.characterOffset(forUTF16Offset: text.utf16.count, in: text) == 4)
        #expect(JournalCursor.utf16Offset(forCharacterOffset: 1, in: text) == 4)
        #expect(JournalCursor.utf16Offset(forCharacterOffset: 3, in: text) == 5 + 8)
    }

    @Test func aLetterWithACombiningMarkIsOneCharacter() {
        let text = "e\u{0301}a"
        #expect(text.count == 2)
        #expect(JournalCursor.characterOffset(forUTF16Offset: 2, in: text) == 1)
        #expect(JournalCursor.utf16Offset(forCharacterOffset: 1, in: text) == 2)
    }

    @Test func chineseIdeographsAreOneUnitEach() {
        #expect(JournalCursor.characterOffset(forUTF16Offset: 2, in: "今天很累") == 2)
        #expect(JournalCursor.utf16Offset(forCharacterOffset: 4, in: "今天很累") == 4)
    }

    @Test func anOffsetInsideACharacterRoundsDownToItsStart() {
        #expect(JournalCursor.characterOffset(forUTF16Offset: 2, in: "a😀b") == 1)
        #expect(JournalCursor.characterOffset(forUTF16Offset: 1, in: "e\u{0301}a") == 0)
    }

    @Test func offsetsPastTheEndOrBelowZeroAreClamped() {
        #expect(JournalCursor.characterOffset(forUTF16Offset: 99, in: "a😀") == 2)
        #expect(JournalCursor.characterOffset(forUTF16Offset: -5, in: "abc") == 0)
        #expect(JournalCursor.utf16Offset(forCharacterOffset: 99, in: "a😀") == 3)
        #expect(JournalCursor.utf16Offset(forCharacterOffset: -1, in: "abc") == 0)
        #expect(JournalCursor.characterOffset(forUTF16Offset: 0, in: "") == 0)
    }

    @Test func theTwoConversionsRoundTripAtEveryCharacterBoundary() {
        let text = "a😀e\u{0301}今🇨🇳z"
        for characters in 0...text.count {
            let units = JournalCursor.utf16Offset(forCharacterOffset: characters, in: text)
            #expect(JournalCursor.characterOffset(forUTF16Offset: units, in: text) == characters)
        }
    }
}
