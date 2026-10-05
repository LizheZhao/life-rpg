import Foundation

/// The live word count of the writing page and the reading page.
///
/// Chinese, Japanese and Korean have no spaces to split on, so each ideograph, kana or hangul
/// syllable counts as one word. Every other maximal run of letters and digits counts as one word,
/// an apostrophe or hyphen between two of its characters keeping the run together ("don't",
/// "well-known"). Punctuation, whitespace and emoji count for nothing.
public enum JournalWords {
    public static func count(_ text: String) -> Int {
        let scalars = Array(text.unicodeScalars)
        var words = 0
        var inRun = false
        for (i, scalar) in scalars.enumerated() {
            if isCJK(scalar) {
                words += 1
                inRun = false
            } else if isWordCharacter(scalar) {
                if !inRun { words += 1 }
                inRun = true
            } else if inRun, connectors.contains(scalar), i + 1 < scalars.count,
                      isWordCharacter(scalars[i + 1]) {
                continue
            } else {
                inRun = false
            }
        }
        return words
    }

    private static let connectors: Set<Unicode.Scalar> = ["'", "\u{2019}", "-", "\u{2010}"]

    /// Letters, digits, and the marks that ride on a letter, so a decomposed accent stays in its word.
    private static func isWordCharacter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber, .nonspacingMark, .spacingMark:
            return true
        default:
            return false
        }
    }

    /// Han ideographs, hiragana, katakana (the middle dot excluded) and hangul.
    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.isIdeographic { return true }
        switch scalar.value {
        case 0x3041...0x3096, 0x30A1...0x30FA, 0x31F0...0x31FF, 0xFF66...0xFF9D,
             0x1100...0x11FF, 0x3131...0x318E, 0xAC00...0xD7A3:
            return true
        default:
            return false
        }
    }
}
