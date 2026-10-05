import Foundation
import Testing
@testable import LifeRPGCore

struct JournalFixedKeyTests {
    private typealias F = EntryFixtures

    @Test func chipLabelsInBothLanguages() {
        #expect(JournalFixedKey.allCases.map { $0.chipLabel(language: .en) }
                == ["Favorite moment", "Grateful for", "Low energy felt like", "Tomorrow"])
        #expect(JournalFixedKey.allCases.map { $0.chipLabel(language: .zhHans) }
                == ["最喜欢的瞬间", "感恩", "低能量的感觉", "明天"])
    }

    @Test func questionTextsInBothLanguages() {
        #expect(JournalFixedKey.allCases.map { $0.question(language: .en) } == [
            "What was your favorite moment today?", "What are you grateful for today?",
            "What did the low energy feel like today?", "What do you want to carry into tomorrow?"])
        #expect(JournalFixedKey.allCases.map { $0.question(language: .zhHans) } == [
            "今天最喜欢的瞬间是什么？", "今天你感恩什么？", "今天低能量是什么感觉？", "你想把什么带进明天？"])
    }

    @Test func theKeysAreStoredByTheirNames() {
        #expect(JournalFixedKey.allCases.map(\.rawValue) == ["favoriteMoment", "gratefulFor", "lowEnergyFeltLike", "tomorrow"])
    }

    @Test func theFallbackOrderIsTheSpecs() {
        #expect(JournalFixedKey.fallbackOrder == [.favoriteMoment, .gratefulFor, .tomorrow, .lowEnergyFeltLike])
        #expect(Set(JournalFixedKey.fallbackOrder) == Set(JournalFixedKey.allCases))
    }

    @Test func theNextFallbackSkipsWhatTheDocumentHolds() {
        #expect(JournalFixedKey.nextFallback(missingFrom: JournalDocument()) == .favoriteMoment)
        #expect(JournalFixedKey.nextFallback(missingFrom: F.doc(F.prompt(1, key: .favoriteMoment))) == .gratefulFor)
        #expect(JournalFixedKey.nextFallback(missingFrom: F.doc(F.prompt(1, key: .favoriteMoment),
                                                                  F.prompt(2, key: .tomorrow))) == .gratefulFor)
        #expect(JournalFixedKey.nextFallback(missingFrom: F.doc(F.prompt(1, key: .favoriteMoment),
                                                                  F.prompt(2, key: .gratefulFor))) == .tomorrow)
        let three = F.doc(F.prompt(1, key: .favoriteMoment), F.prompt(2, key: .gratefulFor), F.prompt(3, key: .tomorrow))
        #expect(JournalFixedKey.nextFallback(missingFrom: three) == .lowEnergyFeltLike)
        let all = F.doc(F.prompt(1, key: .favoriteMoment), F.prompt(2, key: .gratefulFor),
                        F.prompt(3, key: .tomorrow), F.prompt(4, key: .lowEnergyFeltLike))
        #expect(JournalFixedKey.nextFallback(missingFrom: all) == nil)
    }

    @Test func anLLMPromptWithTheSameWordsDoesNotCountAsTheChip() {
        let doc = F.doc(F.prompt(1, "What was your favorite moment today?", source: .llm))
        #expect(!doc.containsFixedKey(.favoriteMoment))
    }
}
