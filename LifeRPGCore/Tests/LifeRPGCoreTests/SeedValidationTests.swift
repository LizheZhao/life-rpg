import Foundation
import Testing
@testable import LifeRPGCore

/// Import-time validation of the two specs. Before this, a typo was stored as-is and the failure
/// was silent: the routine simply never came due, and auto-verification never fired.
struct SeedValidationTests {
    private func routineCSV(spec: String = "MON,THU",
                            kind: String = "weekly",
                            target: String = "2",
                            autoVerify: String = "") -> String {
        """
        text,frequency_kind,frequency_spec,weekly_target,base_points,difficulty,intensity,auto_verify
        Foo,\(kind),"\(spec)",\(target),15,E,low,\(autoVerify)
        """
    }

    private func sideCSV(autoVerify: String) -> String {
        """
        text,difficulty,intensity,hidden_eligible,weekend_only,auto_verify
        Foo,E,low,FALSE,FALSE,\(autoVerify)
        """
    }

    private func seedError(_ body: () throws -> Void) -> SeedError? {
        do { try body(); return nil } catch let error as SeedError { return error } catch { return nil }
    }

    @Test func badFrequencySpecReportsRowAndReason() throws {
        let error = try #require(seedError { _ = try SeedParser.routines(csv: routineCSV(spec: "TUES")) })
        guard case .invalidValue(let row, let column, let value, let reason) = error else {
            Issue.record("expected invalidValue, got \(error)"); return
        }
        #expect(row == 2)
        #expect(column == "frequency_spec")
        #expect(value == "TUES")
        #expect(reason?.contains("TUES") == true)
    }

    @Test(arguments: ["SATURDAY", "MON;THU", "MON,MON"])
    func weekdayTyposThrow(spec: String) {
        #expect(throws: SeedError.self) { try SeedParser.routines(csv: routineCSV(spec: spec, target: "1")) }
    }

    @Test func specIsCheckedAgainstItsKind() {
        // "1:SATURDAY" and a weekly spec under the wrong kind both fail.
        #expect(throws: SeedError.self) {
            try SeedParser.routines(csv: routineCSV(spec: "1:SATURDAY", kind: "nthWeekdayOfMonth", target: "1"))
        }
        #expect(throws: SeedError.self) {
            try SeedParser.routines(csv: routineCSV(spec: "MON", kind: "everyNDays", target: "1"))
        }
    }

    /// A target above the days the spec offers can never be met — every Sunday would report a shortfall.
    @Test func weeklyTargetAboveAvailableDaysThrows() throws {
        let error = try #require(seedError { _ = try SeedParser.routines(csv: routineCSV(spec: "MON", target: "2")) })
        guard case .invalidValue(_, let column, _, _) = error else {
            Issue.record("expected invalidValue, got \(error)"); return
        }
        #expect(column == "weekly_target")
        // A lower target is legitimate: three slots offered, two required.
        #expect(throws: Never.self) {
            try SeedParser.routines(csv: routineCSV(spec: "MON,TUE,WED", target: "2"))
        }
        #expect(throws: SeedError.self) { try SeedParser.routines(csv: routineCSV(target: "0")) }
    }

    @Test func badAutoVerifyThrowsOnBothTables() throws {
        let side = try #require(seedError { _ = try SeedParser.sideQuests(csv: sideCSV(autoVerify: "mindfull:15")) })
        guard case .invalidValue(let row, let column, let value, _) = side else {
            Issue.record("expected invalidValue, got \(side)"); return
        }
        #expect(row == 2)
        #expect(column == "auto_verify")
        #expect(value == "mindfull:15")

        #expect(throws: SeedError.self) {
            try SeedParser.routines(csv: routineCSV(autoVerify: "calendar_workout"))
        }
        // An empty cell stays nil, not an error.
        #expect(try SeedParser.sideQuests(csv: sideCSV(autoVerify: "")).first?.autoVerifyRule == nil)
        #expect(try SeedParser.sideQuests(csv: sideCSV(autoVerify: "mindful:15")).first?.autoVerifyRule == "mindful:15")
    }

    /// The raw string is what gets stored; the parse is only a gate.
    @Test func validSpecIsStoredVerbatim() throws {
        let seed = try #require(try SeedParser.routines(csv: routineCSV(spec: "THU,SUN")).first)
        #expect(seed.spec == "THU,SUN")
        #expect(seed.frequencySpec == .weekly([.sunday, .thursday]))
    }

    @Test func errorDescriptionMentionsLineAndReason() {
        let error = SeedError.invalidValue(row: 7, column: "frequency_spec", value: "TUES", reason: "not a weekday code")
        #expect(String(describing: error) == "line 7, frequency_spec = 'TUES': not a weekday code")
        #expect(String(describing: SeedError.missingColumn("text")) == "CSV is missing the 'text' column")
    }
}
