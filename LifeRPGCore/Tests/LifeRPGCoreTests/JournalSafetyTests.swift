import Foundation
import Testing
@testable import LifeRPGCore

struct JournalSafetyTests {
    @Test func selfHarmAndHopelessnessAreCaughtInEnglish() {
        let hits = [
            "Some days I think about suicide.",
            "I just want to die.",
            "I want to KILL   myself",
            "Everything feels hopeless",
            "I can\u{2019}t go on like this",
            "There is no way out.",
            "i keep wanting to hurt myself",
        ]
        for text in hits { #expect(JournalSafety.needsSafetyLine(answer: text), "\(text)") }
    }

    @Test func selfHarmAndHopelessnessAreCaughtInChinese() {
        let hits = [
            "有时候我想自杀。",
            "真的不想活了",
            "觉得很绝望",
            "我撑不下去了",
            "想伤害自己",
        ]
        for text in hits { #expect(JournalSafety.needsSafetyLine(answer: text), "\(text)") }
    }

    @Test func anOrdinaryDayIsLeftAlone() {
        let misses = [
            "Long day. Finished the report and went for a run.",
            "I killed it at the gym today.",
            "今天走路回家，很安静。",
            "累了，想早点睡。",
            "",
        ]
        for text in misses { #expect(!JournalSafety.needsSafetyLine(answer: text), "\(text)") }
    }

    @Test func theTwoCategoriesAreToldApart() {
        #expect(JournalSafety.categories(in: "I want to die, it is hopeless") == [.selfHarm, .hopelessness])
        #expect(JournalSafety.categories(in: "觉得很绝望") == [.hopelessness])
    }

    @Test func theLineIsThePoolRowInEachLanguage() {
        #expect(JournalSafety.line(language: .en).hasPrefix("That sounds heavy."))
        #expect(JournalSafety.line(language: .zhHans).hasPrefix("听起来很沉重。"))
    }
}
