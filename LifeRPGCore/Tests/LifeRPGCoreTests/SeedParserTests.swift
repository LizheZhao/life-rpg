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
        text,difficulty,intensity,hidden_eligible,weekend_only,cooldown_days,auto_verify,launch_url,variants,notes
        Photograph a set of things in a given color,E,low,TRUE,FALSE,7,,,Red|Blue| Yellow ,Parameterized color
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
        text,frequency_kind,frequency_spec,weekly_target,base_points,difficulty,intensity,flexible_within_week,counts_for_clear,is_active,degraded_text,auto_verify,launch_url,notes
        Go to the office,weekly,"MON,THU",2,5,E,low,FALSE,FALSE,FALSE,,,,"Disabled, for now"
        """
        let r = try #require(try SeedParser.routines(csv: csv).first)
        #expect(r.kind == .weekly)
        #expect(r.spec == "MON,THU")
        #expect(r.weeklyTarget == 2)
        #expect(!r.countsForClear)
        #expect(!r.isActive)
        #expect(r.degradedText == nil)
    }

    @Test func invalidDifficultyReportsRow() {
        let csv = "text,difficulty,intensity,hidden_eligible,weekend_only\nFoo,Z,low,FALSE,FALSE\n"
        #expect(throws: SeedError.invalidValue(row: 2, column: "difficulty", value: "Z")) {
            try SeedParser.sideQuests(csv: csv)
        }
    }

    @Test func missingColumn() {
        #expect(throws: SeedError.missingColumn("weekend_only")) {
            try SeedParser.sideQuests(csv: "text,difficulty,intensity,hidden_eligible\n")
        }
    }

    // MARK: real seed files in doc/

    @Test func realSideQuestsParse() throws {
        let seeds = try SeedParser.sideQuests(csv: Fixtures.csv("side_quests.csv"))
        #expect(seeds.count == 75)
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
        #expect(seeds.count == 13)
        let office = try #require(seeds.first { $0.text == "Go to the office" })
        #expect(!office.isActive)
        let clean = try #require(seeds.first { $0.text.hasPrefix("Clean and tidy") })
        #expect(clean.text == "Clean and tidy the apartment (vacuum, dishes, dust, litter box, water fountain)")
        #expect(clean.degradedText == "Just the litter box and dishes")
        let bills = try #require(seeds.first { $0.text == "Review bills/statements" })
        #expect(bills.kind == .nthWeekdayOfMonth)
        #expect(bills.spec == "-1:SAT")
    }
}
