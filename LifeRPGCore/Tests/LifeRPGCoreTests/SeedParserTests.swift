import Testing
@testable import LifeRPGCore

struct CSVTests {
    @Test func quotedFieldsWithCommasAndEscapes() {
        let rows = CSV.parse("a,\"b, c\",\"say \"\"hi\"\"\"\n1,2,3\n")
        #expect(rows == [["a", "b, c", "say \"hi\""], ["1", "2", "3"]])
    }

    @Test func crlfAndNewlineInsideQuotes() {
        let rows = CSV.parse("a,b\r\n\"x\ny\",z\r\n")
        #expect(rows == [["a", "b"], ["x\ny", "z"]])
    }

    @Test func trailingEmptyFieldsAndBlankLines() {
        let rows = CSV.parse("a,,\n\n1,2,\n")
        #expect(rows == [["a", "", ""], ["1", "2", ""]])
    }

    @Test func noTrailingNewline() {
        #expect(CSV.parse("a,b") == [["a", "b"]])
    }
}

struct DifficultyTests {
    @Test(arguments: [
        ("T", Difficulty.trivial), ("E", .easy), ("M", .medium), ("H", .hard), ("EPIC", .epic), ("epic", .epic),
    ])
    func csvCodes(code: String, expected: Difficulty) {
        #expect(Difficulty(csvCode: code) == expected)
    }

    @Test func unknownCode() {
        #expect(Difficulty(csvCode: "X") == nil)
    }
}

struct SeedParserTests {
    @Test func sideQuestRow() throws {
        let csv = """
        text,difficulty,hidden_eligible,weekend_only,cooldown_days,auto_verify,launch_url,variants,notes
        Photograph a set of things in a given color,E,TRUE,FALSE,7,,,Red|Blue| Yellow ,Parameterized color
        """
        let s = try #require(try SeedParser.sideQuests(csv: csv).first)
        #expect(s.difficulty == .easy)
        #expect(s.hiddenEligible)
        #expect(!s.weekendOnly)
        #expect(s.cooldownDays == 7)
        #expect(s.variants == ["Red", "Blue", "Yellow"])
        #expect(s.launchURLString == nil)
        #expect(s.isActive)   // column absent → active
    }

    @Test func routineRow() throws {
        let csv = """
        text,frequency_kind,frequency_spec,weekly_target,base_points,difficulty,flexible_within_week,counts_for_clear,is_active,downgrade_of,auto_verify,launch_url,notes
        Go to the office,weekly,"MON,THU",2,5,E,FALSE,FALSE,FALSE,,,,"Disabled, for now"
        """
        let r = try #require(try SeedParser.routines(csv: csv).first)
        #expect(r.kind == .weekly)
        #expect(r.spec == "MON,THU")
        #expect(r.weeklyTarget == 2)
        #expect(!r.countsForClear)
        #expect(!r.isActive)
        #expect(r.downgradeOf.isEmpty)
    }

    /// A downgrade version is never scheduled on its own, so it may leave the frequency columns
    /// empty — and `downgrade_of` takes several parents, `|`-separated because routine texts
    /// contain commas.
    @Test func downgradeVersionRow() throws {
        let csv = """
        text,frequency_kind,frequency_spec,weekly_target,base_points,difficulty,flexible_within_week,counts_for_clear,is_active,downgrade_of,auto_verify,launch_url,notes
        "Walk, 30 minutes",,,,10,E,TRUE,TRUE,TRUE,Workout: dumbbell training|Workout: weight training,calendar_workout:30,,
        """
        let r = try #require(try SeedParser.routines(csv: csv).first)
        #expect(r.text == "Walk, 30 minutes")
        #expect(r.basePoints == 10)
        #expect(r.difficulty == .easy)
        #expect(r.downgradeOf == ["Workout: dumbbell training", "Workout: weight training"])
        #expect(r.autoVerifyRule == "calendar_workout:30")
    }

    @Test func invalidDifficultyReportsRow() {
        let csv = "text,difficulty,hidden_eligible,weekend_only\nFoo,Z,FALSE,FALSE\n"
        #expect(throws: SeedError.invalidValue(row: 2, column: "difficulty", value: "Z")) {
            try SeedParser.sideQuests(csv: csv)
        }
    }

    @Test func missingColumn() {
        #expect(throws: SeedError.missingColumn("weekend_only")) {
            try SeedParser.sideQuests(csv: "text,difficulty,hidden_eligible\n")
        }
    }

    // MARK: real seed files in doc/

    @Test func realSideQuestsParse() throws {
        let seeds = try SeedParser.sideQuests(csv: Fixtures.csv("side_quests.csv"))
        #expect(!seeds.isEmpty)
        #expect(Set(seeds.map(\.difficulty)) == Set(Difficulty.allCases))
        let parents = try #require(seeds.first { $0.text == "Video call with parents" })
        #expect(parents.weekendOnly)
        #expect(parents.difficulty == .hard)
        let journal = try #require(seeds.first { $0.text == "Write a journal entry" })
        #expect(journal.variants.count == 5)
        #expect(journal.launchURLString == "obsidian://")
    }

    @Test func realRoutinesParse() throws {
        let seeds = try SeedParser.routines(csv: Fixtures.csv("routine_quests.csv"))
        #expect(!seeds.isEmpty)
        let office = try #require(seeds.first { $0.text == "Go to the office" })
        #expect(!office.isActive)
        let clean = try #require(seeds.first { $0.text.hasPrefix("Clean and tidy") })
        #expect(clean.text == "Clean and tidy the apartment (vacuum, dishes, dust, litter box, water fountain)")
        #expect(clean.downgradeOf.isEmpty)
        let walk = try #require(seeds.first { $0.text == "Walk, 30 minutes" })
        #expect(walk.downgradeOf == ["Workout: dumbbell training", "Workout: weight training"])
        #expect(walk.basePoints == 10)
        let bills = try #require(seeds.first { $0.text == "Review bills/statements" })
        #expect(bills.kind == .nthWeekdayOfMonth)
        #expect(bills.spec == "-1:SAT")
    }

    // MARK: invariants — the merge keys on text, so duplicates would be silently dropped

    @Test func sideQuestTextsAreUnique() throws {
        let texts = try SeedParser.sideQuests(csv: Fixtures.csv("side_quests.csv")).map(\.text)
        #expect(Set(texts).count == texts.count)
    }

    @Test func routineTextsAreUnique() throws {
        let texts = try SeedParser.routines(csv: Fixtures.csv("routine_quests.csv")).map(\.text)
        #expect(Set(texts).count == texts.count)
    }

    @Test func epicsHaveNoCooldown() throws {
        let epics = try SeedParser.sideQuests(csv: Fixtures.csv("side_quests.csv"))
            .filter { $0.difficulty == .epic }
        #expect(!epics.isEmpty)
        #expect(epics.allSatisfy { ($0.cooldownDays ?? 0) == 0 })
    }

    @Test func weekendOnlyQuestsAreHard() throws {
        let weekend = try SeedParser.sideQuests(csv: Fixtures.csv("side_quests.csv"))
            .filter(\.weekendOnly)
        #expect(!weekend.isEmpty)
        #expect(weekend.allSatisfy { $0.difficulty == .hard })
    }
}
