import Foundation
import Testing
@testable import LifeRPGCore

/// The name a person gives the app: kept on the phone, shown in the greeting.
struct UserProfileTests {
    @Test func aNameIsTrimmedAndCollapsed() {
        #expect(UserProfile.cleanName("  Ryo  ") == "Ryo")
        #expect(UserProfile.cleanName("Mary \n Ann") == "Mary Ann")
        #expect(UserProfile.cleanName("李 哲") == "李 哲")
    }

    @Test func nothingBecomesNoName() {
        #expect(UserProfile.cleanName("") == nil)
        #expect(UserProfile.cleanName("   \n ") == nil)
        #expect(UserProfile.cleanName(nil) == nil)
    }

    @Test func aLongNameIsCutAtThirtyCharacters() {
        let name = UserProfile.cleanName(String(repeating: "a", count: 80))
        #expect(name?.count == UserProfile.maxLength && UserProfile.maxLength == 30)
        // cut on characters, not bytes: emoji and Chinese stay whole
        let cut = UserProfile.cleanName(String(repeating: "李", count: 40))
        #expect(cut?.count == 30 && cut?.hasSuffix("李") == true)
    }

    @Test func theGreetingUsesTheNameWhenThereIsOne() {
        let named = TodayGreeting(dayKey: "2026-10-02", hour: 9, streak: 0, name: "Ryo")
        #expect(named.salutation == "Good morning, Ryo,")
        #expect(TodayGreeting(dayKey: "2026-10-02", hour: 15, streak: 0, name: "Ryo").salutation == "Good afternoon, Ryo,")
        #expect(TodayGreeting(dayKey: "2026-10-02", hour: 21, streak: 0, name: "Ryo").salutation == "Good evening, Ryo,")
    }

    @Test func withoutANameTheGreetingIsWhatItWas() {
        #expect(TodayGreeting(dayKey: "2026-10-02", hour: 9, streak: 0).salutation == "Good morning,")
        #expect(TodayGreeting(dayKey: "2026-10-02", hour: 9, streak: 0, name: nil).salutation == "Good morning,")
        #expect(TodayGreeting(dayKey: "2026-10-02", hour: 9, streak: 0, name: "   ").salutation == "Good morning,")
    }

    /// The name is typed by a person into a field the greeting then shows verbatim.
    @Test func aStrangeNameIsStillJustText() {
        #expect(TodayGreeting(dayKey: "2026-10-02", hour: 9, streak: 0, name: "Bob, the \"builder\"").salutation
                == "Good morning, Bob, the \"builder\",")
    }
}
