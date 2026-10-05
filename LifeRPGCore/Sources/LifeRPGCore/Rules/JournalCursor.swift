import Foundation

/// Where a cursor is, in the two units that meet at the editor: UIKit counts UTF-16 code units
/// (`NSRange`), the document operations count `Character`s (`BlockFocus.offset`). An emoji with a
/// skin tone, a flag, a letter with a combining mark and a Chinese ideograph are each one
/// `Character` and between one and eight code units, so the two numbers differ as soon as such a
/// character is typed.
public enum JournalCursor {
    /// The `Character` offset of the UTF-16 offset `utf16` in `text`. An offset inside a character
    /// (UIKit does not put a cursor there, but a selection can reach it) rounds down to the start
    /// of that character. Clamped to the text.
    public static func characterOffset(forUTF16Offset utf16: Int, in text: String) -> Int {
        let target = max(0, utf16)
        var units = 0
        var characters = 0
        for character in text {
            let width = character.utf16.count
            if units + width > target { break }
            units += width
            characters += 1
        }
        return characters
    }

    /// The UTF-16 offset of the start of the `characters`-th `Character` of `text`, clamped to the
    /// text.
    public static func utf16Offset(forCharacterOffset characters: Int, in text: String) -> Int {
        text.prefix(max(0, characters)).utf16.count
    }
}
