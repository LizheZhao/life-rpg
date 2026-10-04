import Testing
@testable import LifeRPGCore

struct JournalStartersTests {
    typealias F = JournalFixtures

    private func texts(_ signals: JournalSignals, habits: JournalHabits = .none,
                       language: JournalLanguage = .en, limit: Int = 4) -> [String] {
        JournalStarters.starters(signals: signals, habits: habits, language: language, limit: limit).map(\.text)
    }

    private func habits(weights: [JournalPromptKind: Double] = [:], used: [String: String] = [:]) -> JournalHabits {
        JournalHabits(medianAnswerLength: nil, typicalHour: nil, usesEmoji: false, weights: weights,
                      starterLastUsedDay: used)
    }

    // MARK: the table

    @Test func everyStarterPassesTheVoiceRulesInBothLanguages() {
        for row in JournalStarters.table {
            #expect(JournalTextCheck.violations(of: row.en, language: .en).isEmpty, "\(row.id)")
            #expect(JournalTextCheck.violations(of: row.zh, language: .zhHans).isEmpty, "\(row.id)")
        }
    }

    @Test func noStarterOpensWithWhyAndIdsAreUnique() {
        for row in JournalStarters.table {
            #expect(!row.en.lowercased().hasPrefix("why"), "\(row.id)")
            #expect(!row.zh.hasPrefix("为什么"), "\(row.id)")
        }
        #expect(Set(JournalStarters.table.map(\.id)).count == JournalStarters.table.count)
    }

    @Test func noStarterIsAQuestionOrEndsInPunctuationItNeedsToContinueFrom() {
        for row in JournalStarters.table {
            #expect(!row.en.contains("?") && !row.zh.contains("？"), "\(row.id)")
        }
    }

    // MARK: the three worked days

    /// djb2("2026-09-18") is odd, so the two fillers (rank 1, never used) come in the order
    /// "I keep thinking about" then "Tomorrow I want to".
    @Test func anOrdinaryDayIsGratefulAndTheFillers() {
        let signals = F.signals(tier: .normal, quests: [F.quest("Walk"), F.quest("Read"), F.quest("Stretch")])
        #expect(texts(signals) == ["Grateful for", "I keep thinking about", "Tomorrow I want to"])
        #expect(JournalStarters.starters(signals: signals, habits: .none, language: .en).first?.id == "starter.grateful")
    }

    @Test func aLowDayWithHeavyRatingsAsksForTheEnergyAndTheWeight() {
        let quests = ["Walk", "Read", "Stretch", "Tidy"].map { F.quest($0) }
        let ratings = zip(quests, [-2, -1, -2, -1]).map { F.rating(of: $0.id, $1) }
        let signals = F.signals(tier: .low, quests: quests, ratings: ratings)
        #expect(signals.averageRating == -1.5)
        #expect(texts(signals) == ["Grateful for", "Low energy felt like", "The heaviest part was",
                                   "I keep thinking about"])
    }

    @Test func aPhotoDayWithASkippedRoutineGetsTheSkipThenTheFavoriteThenTheEye() {
        let photo = F.quest("Take a photo of the sky")
        let missed = F.occurrence("Take out the trash", due: "2026-09-15", skipped: true)
        let signals = F.signals(quests: [photo], occurrences: [missed],
                                ratings: [F.rating(of: photo.id, 2)],
                                ledger: [F.skipEntry(for: missed, on: F.day)])
        #expect(texts(signals) == ["Grateful for", "What got in the way was", "Favorite moment was",
                                   "What caught my eye was"])
    }

    @Test func theSameDayInChineseUsesTheChineseTable() {
        let signals = F.signals(tier: .normal, quests: [F.quest("Walk")])
        #expect(texts(signals, language: .zhHans) == ["今天感恩的是", "我一直在想", "明天我想"])
    }

    // MARK: each rule

    @Test func aVeryLowDayAlsoAsksForTheEnergy() {
        #expect(texts(F.signals(tier: .veryLow)).contains("Low energy felt like"))
        #expect(!texts(F.signals(tier: .normal)).contains("Low energy felt like"))
        #expect(!texts(F.signals(tier: .high)).contains("Low energy felt like"))
    }

    @Test func aRatingOfOneOrMoreGivesTheFavoriteAndZeroDoesNot() {
        let quest = F.quest("Walk")
        #expect(texts(F.signals(quests: [quest], ratings: [F.rating(of: quest.id, 1)])).contains("Favorite moment was"))
        #expect(!texts(F.signals(quests: [quest], ratings: [F.rating(of: quest.id, 0)])).contains("Favorite moment was"))
        #expect(!texts(F.signals(quests: [quest])).contains("Favorite moment was"))
    }

    @Test func aChoiceItemGivesWhatCaughtMyEyeAndAnIncompleteOneDoesNot() {
        #expect(texts(F.signals(quests: [F.quest("Pick a tree to look at")])).contains("What caught my eye was"))
        #expect(!texts(F.signals(quests: [F.quest("Pick a tree to look at", done: false)])).contains("What caught my eye was"))
    }

    @Test func anAverageAtOrBelowMinusOneGivesTheHeaviestPartAndAboveItDoesNot() {
        func average(_ ratings: [Int]) -> JournalSignals {
            let quests = ratings.indices.map { F.quest("Q\($0)") }
            return F.signals(quests: quests, ratings: zip(quests, ratings).map { F.rating(of: $0.id, $1) })
        }
        #expect(texts(average([-1])).contains("The heaviest part was"))
        #expect(texts(average([-2, 0])).contains("The heaviest part was"))
        #expect(!texts(average([-2, 1])).contains("The heaviest part was"))
    }

    @Test func aSkippedRoutineGivesWhatGotInTheWay() {
        let missed = F.occurrence("Take out the trash", due: "2026-09-15", skipped: true)
        let signals = F.signals(occurrences: [missed], ledger: [F.skipEntry(for: missed, on: F.day)])
        #expect(texts(signals).contains("What got in the way was"))
    }

    // MARK: limit, ordering, habits, recency

    @Test func theLimitCutsFromTheEndAndGratefulSurvivesTheTightestOne() {
        let quests = ["Walk", "Read", "Stretch", "Tidy"].map { F.quest($0) }
        let ratings = zip(quests, [-2, -1, -2, -1]).map { F.rating(of: $0.id, $1) }
        let signals = F.signals(tier: .low, quests: quests, ratings: ratings)
        #expect(texts(signals, limit: 1) == ["Grateful for"])
        #expect(texts(signals, limit: 2) == ["Grateful for", "Low energy felt like"])
        #expect(texts(signals, limit: 0) == [])
        #expect(texts(signals, limit: 20).count == 5)
    }

    @Test func theDefaultLimitIsFour() {
        let quests = ["Walk", "Read", "Stretch", "Tidy"].map { F.quest($0) }
        let ratings = zip(quests, [-2, -1, -2, -1]).map { F.rating(of: $0.id, $1) }
        let signals = F.signals(tier: .low, quests: quests, ratings: ratings)
        #expect(JournalStarters.starters(signals: signals, habits: .none, language: .en).count == 4)
    }

    @Test func aKindTheUserKeepsSkippingFallsBehindTheOnesTheyAnswer() {
        let photo = F.quest("Take a photo of the sky")
        let missed = F.occurrence("Take out the trash", due: "2026-09-15", skipped: true)
        let signals = F.signals(quests: [photo], occurrences: [missed], ratings: [F.rating(of: photo.id, 2)],
                                ledger: [F.skipEntry(for: missed, on: F.day)])
        // skip 3 * 0.25 = 0.75 drops under the favorite (2.5), the eye (2) and even a filler (1).
        let quiet = habits(weights: [.skip: 0.25])
        #expect(texts(signals, habits: quiet)
                == ["Grateful for", "Favorite moment was", "What caught my eye was", "I keep thinking about"])
        #expect(texts(signals, habits: quiet, limit: 6).last == "What got in the way was")
    }

    @Test func aFillerUsedYesterdayYieldsToTheOneNotUsed() {
        let signals = F.signals(quests: [F.quest("Walk")])
        let used = habits(used: ["starter.thinking": "2026-09-17"])
        #expect(texts(signals, habits: used) == ["Grateful for", "Tomorrow I want to", "I keep thinking about"])
        let other = habits(used: ["starter.tomorrow": "2026-09-17"])
        #expect(texts(signals, habits: other) == ["Grateful for", "I keep thinking about", "Tomorrow I want to"])
    }

    @Test func theFillersRotateByTheDayWithNoHistory() {
        func first(_ day: String) -> String {
            texts(F.signals(quests: [F.quest("Walk", on: day)], on: day))[1]
        }
        let seen = Set((10...19).map { first("2026-09-\($0)") })
        #expect(seen == ["I keep thinking about", "Tomorrow I want to"])
        #expect(first("2026-09-18") == first("2026-09-18"))
    }

    @Test func aFactBasedStarterBeatsAFillerEvenIfItWasUsedYesterday() {
        let signals = F.signals(tier: .low)
        let used = habits(used: ["starter.lowEnergy": "2026-09-17"])
        #expect(texts(signals, habits: used).prefix(2) == ["Grateful for", "Low energy felt like"])
    }

    // MARK: recency read from the turns

    @Test func aParagraphThatBeginsWithAStarterCountsAsUsingItThatDay() {
        let writing = F.freeWriting("Grateful for the rain.\n\nTomorrow I want to rest.\nAnd more.", on: "2026-09-17")
        let derived = JournalHabits.derive(from: [writing, F.turn(.opening, "I keep thinking about it", index: 0, on: "2026-09-10")],
                                           asOf: "2026-09-18", timeZone: Fixtures.tokyo)
        #expect(derived.starterLastUsedDay == ["starter.grateful": "2026-09-17", "starter.tomorrow": "2026-09-17",
                                               "starter.thinking": "2026-09-10"])
    }

    @Test func aStarterInTheMiddleOfAParagraphIsNotUse() {
        let writing = F.freeWriting("I wrote Tomorrow I want to somewhere\n\nbut Grateful for was not first", on: "2026-09-17")
        let derived = JournalHabits.derive(from: [writing], asOf: "2026-09-18", timeZone: Fixtures.tokyo)
        #expect(derived.starterLastUsedDay.isEmpty)
    }

    @Test func theLatestDayWinsAndChineseStartersAreRecognised() {
        let turns = [F.freeWriting("今天感恩的是雨", on: "2026-09-12"), F.freeWriting("今天感恩的是茶", on: "2026-09-16")]
        let derived = JournalHabits.derive(from: turns, asOf: "2026-09-18", timeZone: Fixtures.tokyo)
        #expect(derived.starterLastUsedDay == ["starter.grateful": "2026-09-16"])
    }

    @Test func aStarterUsedTodayDoesNotCountBecauseHabitsReadTheDaysBeforeToday() {
        let writing = F.freeWriting("Grateful for rain", on: "2026-09-18")
        let derived = JournalHabits.derive(from: [writing], asOf: "2026-09-18", timeZone: Fixtures.tokyo)
        #expect(derived.starterLastUsedDay.isEmpty)
    }

    // MARK: inserting

    private func starter(_ text: String = "Grateful for") -> JournalStarter {
        JournalStarter(id: "starter.grateful", kind: .good, text: text)
    }

    @Test func insertOntoAnEmptyPageIsThePhraseAndASpace() {
        #expect(starter().insert(into: "") == "Grateful for ")
    }

    @Test func insertOntoAPageOfOnlyWhitespaceIsTheSameAsEmpty() {
        #expect(starter().insert(into: " \n\n ") == "Grateful for ")
    }

    @Test func insertOntoTextGoesAfterABlankLineAndTrimsTheTrailingWhitespace() {
        #expect(starter().insert(into: "A walk.") == "A walk.\n\nGrateful for ")
        #expect(starter().insert(into: "A walk.  \n\n\n") == "A walk.\n\nGrateful for ")
    }

    @Test func insertKeepsTheTextBeforeItAsItWasIncludingLeadingAndInternalSpace() {
        #expect(starter().insert(into: "  one\n\n  two ") == "  one\n\n  two\n\nGrateful for ")
    }

    @Test func insertingTwiceStacksParagraphs() {
        let once = starter("Grateful for").insert(into: "")
        #expect(starter("Tomorrow I want to").insert(into: once) == "Grateful for\n\nTomorrow I want to ")
    }
}
