import Foundation
import Testing
@testable import LifeRPGCore

struct JournalTrendsPageTests {
    private let tz = Fixtures.tokyo
    private let english = Locale(identifier: "en_US")

    /// Eight written days in September, 10 to 17 September, 100 words each unless told otherwise.
    private func september(_ extra: [(String, Int)] = []) -> [(String, Int)] {
        (10...17).map { (String(format: "2026-09-%02d", $0), 100) } + extra
    }

    private func page(_ period: JournalTrends.Period = .month, anchor: String = "2026-09-18",
                      today: String = "2026-09-18", spec: [(String, Int)]? = nil,
                      texts: [(String, String)]? = nil, entries: [JournalEntryDay]? = nil, quests: [DailyQuest] = [],
                      occurrences: [RoutineOccurrence] = [], ratings: [QuestRating] = [],
                      contexts: [DailyContext] = [], language: JournalLanguage = .en,
                      locale: Locale? = nil) -> TrendsPage {
        let days = entries ?? texts.map { TrendsFixtures.entryDays(texts: $0) }
            ?? TrendsFixtures.entryDays(spec ?? september())
        return TrendsPage.build(period: period, anchor: anchor, today: today, days: days, quests: quests,
                                occurrences: occurrences, ratings: ratings, contexts: contexts,
                                language: language, timeZone: tz, locale: locale ?? english)
    }

    private func unlocked(_ page: TrendsPage) -> TrendsPage.Unlocked {
        guard case .unlocked(let value) = page.content else { Issue.record("page is locked"); fatalError() }
        return value
    }

    // MARK: locked

    @Test func underSevenNightsThePageIsTheLockedCardWithTheRealCount() {
        let result = page(spec: [("2026-09-16", 10), ("2026-09-17", 10), ("2026-09-18", 10)])
        #expect(result.subtitle == "unlocks after 7 nights")
        guard case .locked(let locked) = result.content else { Issue.record("expected locked"); return }
        #expect(locked.progress.text == "3 of 7 nights written")
        // The wording itself is pinned in JournalTrendsLockedTests.
        #expect(locked.explanation == JournalTrends.Locked.explanation)
        #expect(locked.previews == JournalTrends.Locked.previews)
    }

    @Test func noEntriesIsZeroOfSevenAndTheLockCountsNightsOverAllTimeNotThePeriod() {
        guard case .locked(let none) = page(spec: []).content else { Issue.record("expected locked"); return }
        #expect(none.progress.text == "0 of 7 nights written")
        // Seven nights, all in August: September is empty and the page is still unlocked.
        let august = (1...7).map { (String(format: "2026-08-%02d", $0), 50) }
        let result = page(spec: august)
        #expect(result.subtitle == "September \u{00B7} 0 entries")
        #expect(unlocked(result).totalWords == 0)
    }

    // MARK: subtitle and navigation

    @Test func theSubtitleNamesThePeriodAndCountsItsEntries() {
        #expect(page(.month).subtitle == "September \u{00B7} 8 entries")
        #expect(page(.week, anchor: "2026-09-16").subtitle == "Sep 14 \u{2013} Sep 20 \u{00B7} 4 entries")
        #expect(page(.year).subtitle == "2026 \u{00B7} 8 entries")
    }

    @Test func oneEntryIsNotEntries() {
        let spec = (1...7).map { (String(format: "2026-08-%02d", $0), 5) } + [("2026-09-02", 5)]
        #expect(page(spec: spec).subtitle == "September \u{00B7} 1 entry")
    }

    @Test func theControlsLeadBackOnlyToWrittenHistoryAndNeverPastToday() {
        let current = page(.month)
        #expect(current.nextAnchor == nil)
        // Nothing before September 10th, so nothing before September.
        #expect(current.previousAnchor == nil)

        let withAugust = september((1...3).map { (String(format: "2026-08-%02d", $0), 10) })
        let result = page(.month, spec: withAugust)
        #expect(result.previousAnchor == "2026-08-31")
        let august = page(.month, anchor: "2026-08-31", spec: withAugust)
        #expect(august.subtitle == "August \u{00B7} 3 entries")
        #expect(august.nextAnchor == "2026-09-01")
        #expect(august.previousAnchor == nil)
        #expect(page(.week, anchor: "2026-09-02", spec: withAugust).nextAnchor == "2026-09-07")
    }

    @Test func anEntryWithNothingWrittenLeadsNowhereAndIsNotCounted() {
        let blank = TrendsFixtures.day("2026-08-31", [EntryFixtures.prompt(1, "Asked", answer: "")])
        let days = TrendsFixtures.entryDays(september()) + [blank]
        let result = TrendsPage.build(period: .month, anchor: "2026-09-18", today: "2026-09-18", days: days,
                                      quests: [], occurrences: [], ratings: [], contexts: [], language: .en,
                                      timeZone: tz, locale: english)
        #expect(result.previousAnchor == nil)
        #expect(result.subtitle == "September \u{00B7} 8 entries")
    }

    // MARK: stats

    @Test func theTilesAreTheWordsTheStreakAndTheUsualHourInTheLocalesForm() {
        let result = unlocked(page(.month, spec: september([("2026-09-18", 50)])))
        #expect(result.totalWords == 850)
        #expect(result.streak == 9)
        let hour = result.usualHour?.replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        #expect(hour == "10 PM")
        let german = unlocked(page(.month, spec: september(), locale: Locale(identifier: "de_DE")))
        #expect(german.usualHour == "22 Uhr")
    }

    @Test func aPeriodWithNothingWrittenHasZeroWordsNoUsualHourAndNoChartSections() {
        // Writing, quests, a low day and gratitude, all 10 to 17 September; the week shown is the one
        // before, so each section is empty only if it is cut to the week.
        let thanks = (10...17).map {
            TrendsFixtures.day(String(format: "2026-09-%02d", $0), [grateful("tea")])
        }
        let contexts = [JournalFixtures.context(tier: .low, on: "2026-09-11")]
        let result = unlocked(page(.week, anchor: "2026-09-02", entries: thanks, quests: walk(), contexts: contexts))
        #expect(result.totalWords == 0)
        #expect(result.usualHour == nil)
        #expect(result.wordsPerDay == nil)
        #expect(result.about == nil)
        #expect(result.calendar.isEmpty)
        #expect(result.favorites == nil)
        #expect(result.energy == nil)
        #expect(result.gratitude.isEmpty)
        // The streak is all-time: 10 to 17 September, outside the empty week's rows.
        #expect(result.streak == 8)
    }

    // MARK: words per day

    @Test func everyDayOfThePeriodIsABarAgainstTheLongestAndAQuietDayIsEmpty() {
        let result = unlocked(page(.week, anchor: "2026-09-16", spec: september([("2026-09-18", 25)])
            .map { $0.0 == "2026-09-15" ? ($0.0, 400) : $0 }))
        let chart = try! #require(result.wordsPerDay)
        #expect(chart.bars.map(\.dayKey) == ["2026-09-14", "2026-09-15", "2026-09-16", "2026-09-17",
                                              "2026-09-18", "2026-09-19", "2026-09-20"])
        #expect(chart.bars.map(\.words) == [100, 400, 100, 100, 25, 0, 0])
        #expect(chart.bars.map(\.fraction) == [0.25, 1, 0.25, 0.25, 0.0625, 0, 0])
        // Five written days, so the 90th percentile is the longest: only the 400 is darkest.
        #expect(chart.bars.map(\.isTop) == [false, true, false, false, false, false, false])
        // 5 written days of 100, 400, 100, 100, 25: average 145.
        #expect(chart.average == 145)
        #expect(chart.axis == ["Sep 14", "Sep 17", "Sep 20"])
    }

    @Test func aMonthsAxisIsItsFirstMiddleAndLastDate() {
        let chart = try! #require(unlocked(page(.month)).wordsPerDay)
        #expect(chart.bars.count == 30)
        #expect(chart.axis == ["Sep 1", "Sep 15", "Sep 30"])
    }

    @Test func aDayOfOnlyEmojiIsAnEntryWithAnEmptyBar() {
        let texts = (10...16).map { (String(format: "2026-09-%02d", $0), "word word") } + [("2026-09-17", "\u{1F600}")]
        let built = page(.week, anchor: "2026-09-17", texts: texts)
        #expect(built.subtitle == "Sep 14 \u{2013} Sep 20 \u{00B7} 4 entries")
        let result = unlocked(built)
        let bar = try! #require(result.wordsPerDay?.bars.first { $0.dayKey == "2026-09-17" })
        #expect(bar.words == 0)
        #expect(bar.fraction == 0)
        #expect(!bar.isTop)
        // The entry is still an entry, so its heat cell is the lightest tier rather than blank.
        #expect(result.calendar.first { $0.dayKey == "2026-09-17" }?.level == 1)
    }

    // MARK: words

    @Test func theWordListIsTheTopFiveOfThePeriodVersusTheOtherMonthsWithTheTitleOfThePeriod() {
        // On separate days, so the two words are never an adjacent pair that would read as a phrase.
        var texts = (10...13).map { (String(format: "2026-09-%02d", $0), "water water") }
        texts += (14...17).map { (String(format: "2026-09-%02d", $0), "ownership ownership ownership") }
        texts += (1...2).map { (String(format: "2026-08-%02d", $0), "tea tea tea tea") }
        let result = unlocked(page(.month, texts: texts))
        let about = try! #require(result.about)
        #expect(about.kind == .distinctive)
        #expect(about.title == "What this month was about")
        #expect(about.subtitle == "Words that stood out versus your other months")
        #expect(about.rows.map(\.word) == ["ownership", "water"])
        #expect(about.rows.map(\.count) == [12, 8])
        #expect(about.rows.map(\.fraction) == [1, 8.0 / 12.0])

        #expect(unlocked(page(.week, anchor: "2026-09-16", texts: texts)).about?.title == "What this week was about")
        // A year with no other year to compare against is labelled for what it is.
        let lonely = unlocked(page(.year, texts: texts)).about
        #expect(lonely?.kind == .mostUsed)
        #expect(lonely?.subtitle == "Most used words")
        #expect(lonely?.title == "What this year was about")
        let withLastYear = unlocked(page(.year, texts: texts + [("2025-12-31", "tea tea")])).about
        #expect(withLastYear?.kind == .distinctive)
        #expect(withLastYear?.subtitle == "Words that stood out versus your other years")
    }

    @Test func withOnlyThisMonthWrittenTheListIsMostUsedWordsInPlainCounts() {
        let texts = (10...17).map { (String(format: "2026-09-%02d", $0), "water water. Tea.") }
        let about = try! #require(unlocked(page(.month, texts: texts)).about)
        #expect(about.kind == .mostUsed)
        #expect(about.subtitle == "Most used words")
        #expect(about.rows.map(\.word) == ["water", "tea"])
        #expect(about.rows.map(\.count) == [16, 8])
    }

    @Test func theBarsAreAgainstTheCommonestWordEvenWhenARarerOneRanksFirst() {
        // "running" is said four times but every other month says it a lot too; "kayak" is new.
        var texts = [("2026-09-10", "running running running running"), ("2026-09-11", "kayak kayak kayak")]
        texts += zip(12...17, ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot"]).map { (String(format: "2026-09-%02d", $0), $1) }
        texts += (1...3).map { (String(format: "2026-08-%02d", $0), "running running running running running running") }
        let about = try! #require(unlocked(page(.month, texts: texts)).about)
        #expect(about.rows.map(\.word) == ["kayak", "running"])
        #expect(about.rows.map(\.fraction) == [0.75, 1])
    }

    @Test func chineseEntriesGetChineseWords() {
        let texts = (10...17).map { (String(format: "2026-09-%02d", $0), "今天去散步了，散步很开心，散步之后喝了茶") }
        let about = unlocked(page(.month, texts: texts, language: .zhHans)).about
        #expect(about?.rows.map(\.word).contains("散步") == true)
    }

    private func grateful(_ answer: String) -> JournalBlock {
        EntryFixtures.prompt(1, "What are you grateful for today?", answer: answer, key: .gratefulFor)
    }

    // MARK: calendar, gratitude, year

    @Test func theHeatGridHasACellPerDayAtTheTierOfItsWords() {
        let result = unlocked(page(.week, anchor: "2026-09-16"))
        #expect(result.calendar.map(\.dayKey) == ["2026-09-14", "2026-09-15", "2026-09-16", "2026-09-17",
                                                   "2026-09-18", "2026-09-19", "2026-09-20"])
        // 100 words a day is the middle tier of the glyph's bands.
        #expect(result.calendar.map(\.level) == [2, 2, 2, 2, 0, 0, 0])
    }

    @Test func gratitudeIsThePeriodsMostOftenPhrasesAndAbsentWhenThereAreNone() {
        var entries = (10...16).map { TrendsFixtures.day(String(format: "2026-09-%02d", $0), text: "Quiet day.") }
        entries += [TrendsFixtures.day("2026-09-17", [grateful("the walk, the cat")]),
                    TrendsFixtures.day("2026-09-18", [grateful("the walk")])]
        let result = unlocked(page(.month, entries: entries))
        #expect(result.gratitude.map(\.text) == ["the walk", "the cat"])
        #expect(result.gratitude.map(\.count) == [2, 1])
        #expect(unlocked(page(.month)).gratitude.isEmpty)
    }

    @Test func theYearAtAGlanceIsTwelveCirclesShadedByEntriesOfTheYearOfThePeriod() {
        let spec = september() + (1...12).map { (String(format: "2026-08-%02d", $0), 10) }
            + [("2025-12-30", 10)]
        let circles = unlocked(page(.month, spec: spec)).year
        #expect(circles.count == 12)
        #expect(circles.map(\.label).prefix(3) == ["Jan", "Feb", "Mar"])
        #expect(circles[7].entries == 12 && circles[7].level == 2)
        #expect(circles[8].entries == 8 && circles[8].level == 1)
        #expect(circles[0].entries == 0 && circles[0].level == 0)
        #expect(circles[11].entries == 0)
    }

    // MARK: quests and energy

    private func walk() -> [DailyQuest] {
        (10...12).map { JournalFixtures.quest("Walk", on: String(format: "2026-09-%02d", $0)) }
    }

    @Test func favoritesSayHowOftenAndHowManyWereLight() {
        let id = UUID()
        let routines = (10...13).map { day -> RoutineOccurrence in
            let o = JournalFixtures.routineDone("Stretch", on: String(format: "2026-09-%02d", day))
            o.routineID = id
            if day > 11 { o.degradedRoutineID = UUID(); o.usedDegraded = true }
            return o
        }
        let result = unlocked(page(.month, quests: walk(), occurrences: routines))
        let favorites = try! #require(result.favorites)
        #expect(favorites.subtitle == "Done most and rated best this month")
        #expect(favorites.rows.map(\.text) == ["Stretch", "Walk"])
        #expect(favorites.rows.map(\.detail) == ["4 times \u{00B7} light version 2", "3 times"])
        #expect(favorites.rows.map(\.stars) == [nil, nil])
        #expect(unlocked(page(.month)).favorites == nil)
    }

    @Test func aSingleCompletionIsOneTime() {
        let one = [JournalFixtures.quest("Walk", on: "2026-09-10")]
        #expect(unlocked(page(.month, quests: one)).favorites?.rows.first?.detail == "1 time")
    }

    @Test func theEnergyBarsAndTheFooterAreInPointsNotInQuestsDone() {
        let tiers: [(String, Tier)] = [("2026-09-10", .normal), ("2026-09-11", .normal), ("2026-09-12", .normal),
                                       ("2026-09-13", .low), ("2026-09-14", .low), ("2026-09-15", .low)]
        // A normal day is one 30-point quest, a low day two 5-point ones: more quests, fewer points.
        var quests: [DailyQuest] = []
        for (index, (key, _)) in tiers.enumerated() {
            for points in index < 3 ? [30] : [5, 5] {
                let quest = JournalFixtures.quest("Q", on: key)
                quest.points = points
                quests.append(quest)
            }
        }
        let contexts = tiers.map { JournalFixtures.context(tier: $0.1, on: $0.0) }
        let energy = try! #require(unlocked(page(.month, quests: quests, contexts: contexts)).energy)
        #expect(energy.bars.map(\.fraction) == [1, 1, 1, 1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0])
        #expect(energy.lowDayPercent == 33)
    }

    @Test func lowEnergyShowsOnlyWithALowDayAndTheCalloutOnlyWithEnoughDaysOfEachKind() {
        let tiers: [(String, Tier)] = [("2026-09-10", .normal), ("2026-09-11", .normal), ("2026-09-12", .normal),
                                       ("2026-09-13", .veryLow), ("2026-09-14", .low), ("2026-09-15", .veryLow)]
        let contexts = tiers.map { JournalFixtures.context(tier: $0.1, on: $0.0) }
        // Each fixture quest pays 10: normal days earn 70, low days 50, so 71% of a normal day.
        var quests: [DailyQuest] = []
        for (key, count) in [("2026-09-10", 7), ("2026-09-11", 7), ("2026-09-12", 7),
                             ("2026-09-13", 5), ("2026-09-14", 5), ("2026-09-15", 5)] {
            quests += (0..<count).map { _ in JournalFixtures.quest("Q", on: key) }
        }
        let energy = try! #require(unlocked(page(.month, quests: quests, contexts: contexts)).energy)
        #expect(energy.bars.map(\.dayKey) == tiers.map(\.0))
        #expect(energy.bars.map(\.isLow) == [false, false, false, true, true, true])
        #expect(energy.bars.map(\.fraction) == [1, 1, 1, 5.0 / 7.0, 5.0 / 7.0, 5.0 / 7.0])
        #expect(energy.lowDayPercent == 71)

        let fewLow = try! #require(unlocked(page(.month, quests: quests, contexts: Array(contexts.prefix(4)))).energy)
        #expect(fewLow.lowDayPercent == nil)

        let noLow = contexts.prefix(3).map { $0 }
        #expect(unlocked(page(.month, quests: quests, contexts: noLow)).energy == nil)
        #expect(unlocked(page(.month, quests: quests)).energy == nil)
    }
}
