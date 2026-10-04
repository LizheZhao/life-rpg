import Foundation
import Testing
@testable import LifeRPGCore

struct JournalShortcutLinkTests {
    @Test func theRunURLNamesTheShortcutAndTheThreeReturnLinksAndNothingElse() throws {
        let url = try #require(JournalShortcutLink.runURL(shortcutName: "Journal"))
        #expect(url.absoluteString == "shortcuts://x-callback-url/run-shortcut?name=Journal"
            + "&x-success=liferpg://journal-saved&x-cancel=liferpg://journal-cancelled&x-error=liferpg://journal-failed")
    }

    @Test func aNameWithSpacesAmpersandsAndChineseIsPercentEncodedAndTrimmed() throws {
        let url = try #require(JournalShortcutLink.runURL(shortcutName: "  Evening & notes 日记 "))
        #expect(url.absoluteString.hasPrefix(
            "shortcuts://x-callback-url/run-shortcut?name=Evening%20%26%20notes%20%E6%97%A5%E8%AE%B0&x-success="))
    }

    @Test func aBlankNameHasNoURL() {
        #expect(JournalShortcutLink.runURL(shortcutName: "") == nil)
        #expect(JournalShortcutLink.runURL(shortcutName: "  \n ") == nil)
    }

    @Test func returnLinksAreReadBackAndOtherURLsAreIgnored() throws {
        #expect(JournalShortcutLink.outcome(of: try #require(URL(string: "liferpg://journal-saved"))) == .saved)
        #expect(JournalShortcutLink.outcome(of: try #require(URL(string: "liferpg://journal-cancelled"))) == .cancelled)
        #expect(JournalShortcutLink.outcome(of: try #require(URL(string: "liferpg://journal-failed?errorMessage=x"))) == .failed)
        #expect(JournalShortcutLink.outcome(of: try #require(URL(string: "liferpg://something-else"))) == nil)
        #expect(JournalShortcutLink.outcome(of: try #require(URL(string: "https://journal-saved"))) == nil)
    }
}
