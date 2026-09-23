import Foundation
import Testing
@testable import LifeRPGCore

struct FrequencySpecTests {
    @Test func weeklySortsAndKeepsAllDays() throws {
        #expect(try FrequencySpec.parse(kind: .weekly, spec: "MON,THU") == .weekly([.monday, .thursday]))
        #expect(try FrequencySpec.parse(kind: .weekly, spec: "SAT,SUN") == .weekly([.sunday, .saturday]))
        #expect(try FrequencySpec.parse(kind: .weekly, spec: " sat , mon ") == .weekly([.monday, .saturday]))
        #expect(try FrequencySpec.parse(kind: .weekly, spec: "FRI") == .weekly([.friday]))
    }

    @Test func otherKinds() throws {
        #expect(try FrequencySpec.parse(kind: .everyNDays, spec: "3") == .everyNDays(3))
        #expect(try FrequencySpec.parse(kind: .monthly, spec: "15") == .monthly(day: 15))
        #expect(try FrequencySpec.parse(kind: .nthWeekdayOfMonth, spec: "1:SAT")
                == .nthWeekdayOfMonth(n: 1, weekday: .saturday))
        #expect(try FrequencySpec.parse(kind: .nthWeekdayOfMonth, spec: "-1:SAT")
                == .nthWeekdayOfMonth(n: -1, weekday: .saturday))
        #expect(try FrequencySpec.parse(kind: .everyNWeeksOnWeekday, spec: "2:SAT")
                == .everyNWeeksOnWeekday(n: 2, weekday: .saturday))
    }

    /// The whole point: a typo throws instead of the routine silently never coming due.
    @Test(arguments: [
        (RecurrenceKind.weekly, "TUES"),
        (.weekly, "SATURDAY"),
        (.weekly, "MON,"),
        (.weekly, "MON,MON"),
        (.weekly, "MON;THU"),
        (.weekly, ""),
        (.weekly, "3"),
        (.everyNDays, "SAT"),
        (.everyNDays, "0"),
        (.everyNDays, "2.5"),
        (.monthly, "0"),
        (.monthly, "32"),
        (.nthWeekdayOfMonth, "1:SATURDAY"),
        (.nthWeekdayOfMonth, "SAT"),
        (.nthWeekdayOfMonth, "5:SAT"),
        (.nthWeekdayOfMonth, "6:SAT"),
        (.nthWeekdayOfMonth, "-2:SAT"),
        (.nthWeekdayOfMonth, "1:SAT:2"),
        (.everyNWeeksOnWeekday, "0:SAT"),
        (.everyNWeeksOnWeekday, "2"),
    ])
    func typosThrow(kind: RecurrenceKind, spec: String) {
        #expect(throws: FrequencyError.self) {
            try FrequencySpec.parse(kind: kind, spec: spec)
        }
    }

    @Test func specStringRoundTrips() throws {
        for (kind, spec) in [(RecurrenceKind.weekly, "MON,THU"), (.everyNDays, "3"), (.monthly, "15"),
                             (.nthWeekdayOfMonth, "-1:SAT"), (.everyNWeeksOnWeekday, "2:SAT")] {
            let parsed = try FrequencySpec.parse(kind: kind, spec: spec)
            #expect(parsed.specString == spec)
            #expect(parsed.kind == kind)
            #expect(try FrequencySpec.parse(kind: kind, spec: parsed.specString) == parsed)
        }
    }

    @Test func nominalWeeklyCountOnlyForWeeklyKinds() throws {
        #expect(try FrequencySpec.parse(kind: .weekly, spec: "MON,TUE,WED").nominalWeeklyCount == 3)
        #expect(try FrequencySpec.parse(kind: .everyNWeeksOnWeekday, spec: "2:SAT").nominalWeeklyCount == nil)
        #expect(try FrequencySpec.parse(kind: .nthWeekdayOfMonth, spec: "1:SAT").nominalWeeklyCount == nil)
    }

    @Test func weekdayCodes() {
        #expect(Weekday(code: "sun") == .sunday)
        #expect(Weekday(code: " SAT ") == .saturday)
        #expect(Weekday(code: "TUES") == nil)
        #expect(Weekday.saturday.isWeekend && Weekday.sunday.isWeekend)
        #expect(!Weekday.friday.isWeekend)
        // Raw values line up with Calendar's weekday component.
        #expect(Weekday.allCases.map(\.rawValue) == Array(1...7))
    }

    /// Every spec in the real CSV parses — otherwise that routine would never come due.
    @Test func realRoutineSpecsParse() throws {
        let seeds = try SeedParser.routines(csv: Fixtures.csv("routine_quests.csv"))
        // A downgrade version has no frequency of its own: it is only ever reached through the
        // routine that offers it.
        for seed in seeds where seed.downgradeOf.isEmpty {
            let parsed = try FrequencySpec.parse(kind: seed.kind, spec: seed.spec)
            #expect(parsed.kind == seed.kind)
            if let available = parsed.nominalWeeklyCount {
                #expect(seed.weeklyTarget <= available)
            }
        }
    }
}

struct AutoVerifyRuleTests {
    @Test func validRules() throws {
        #expect(try AutoVerifyRule.parse("mindful:15") == .mindful(minutes: 15))
        #expect(try AutoVerifyRule.parse("calendar_workout:30") == .calendarWorkout(minutes: 30))
        #expect(try AutoVerifyRule.parse(" CALENDAR_WORKOUT_WEEKLY : 4 ") == .calendarWorkoutWeekly(sessions: 4))
    }

    @Test(arguments: ["mindful", "mindful:", "mindful:0", "mindful:-5", "mindful:15:20",
                      "mindfull:15", "calendar_workouts:30", "workout:30", "mindful:fifteen", ""])
    func typosThrow(rule: String) {
        #expect(throws: AutoVerifyError.self) { try AutoVerifyRule.parse(rule) }
    }

    @Test func weeklyFlagAndRoundTrip() throws {
        #expect(try AutoVerifyRule.parse("calendar_workout_weekly:4").isWeekly)
        #expect(try !AutoVerifyRule.parse("calendar_workout:20").isWeekly)
        for rule in ["mindful:15", "calendar_workout:20", "calendar_workout_weekly:4"] {
            #expect(try AutoVerifyRule.parse(rule).ruleString == rule)
        }
    }

    /// Every rule in both real CSVs parses — otherwise auto-verification quietly never fires.
    @Test func realRulesParse() throws {
        let side = try SeedParser.sideQuests(csv: Fixtures.csv("side_quests.csv")).compactMap(\.autoVerifyRule)
        let routines = try SeedParser.routines(csv: Fixtures.csv("routine_quests.csv")).compactMap(\.autoVerifyRule)
        #expect(!side.isEmpty && !routines.isEmpty)
        for rule in side + routines {
            #expect(throws: Never.self) { try AutoVerifyRule.parse(rule) }
        }
    }
}
