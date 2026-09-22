import Foundation
import Testing
@testable import LifeRPGCore

/// Monday-start month grid, one ISO week per row.
struct MonthGridTests {
    private let tz = Fixtures.tokyo

    @Test func monthKeyParsesAndSteps() {
        let sep = MonthKey(dayKey: "2026-09-17")!
        #expect(sep.description == "2026-09")
        #expect(sep.firstDayKey == "2026-09-01")
        #expect(sep.adding(1).description == "2026-10")
        #expect(sep.adding(4).description == "2027-01")
        #expect(sep.adding(-9).description == "2025-12")
        #expect(MonthKey(dayKey: "2026-9-17") == nil)
        #expect(MonthKey(dayKey: "2026-13-01") == nil)
    }

    /// September 2026 starts on a Tuesday and ends on a Wednesday: five rows, Aug 31 … Oct 4.
    @Test func september2026() {
        let grid = MonthGrid(MonthKey(year: 2026, month: 9)!, in: tz)
        #expect(grid.weeks.count == 5)
        #expect(grid.weeks.allSatisfy { $0.days.count == 7 })
        #expect(grid.weeks.first?.days.first?.dayKey == "2026-08-31")
        #expect(grid.weeks.first?.days.first?.inMonth == false)
        #expect(grid.weeks.first?.days[1].dayKey == "2026-09-01")
        #expect(grid.weeks.first?.days[1].dayOfMonth == 1)
        #expect(grid.weeks.last?.days.last?.dayKey == "2026-10-04")
        #expect(grid.weeks.map(\.weekKey) == ["2026-W36", "2026-W37", "2026-W38", "2026-W39", "2026-W40"])
        #expect(grid.weeks.flatMap(\.days).filter(\.inMonth).count == 30)
    }

    /// February 2027 starts on a Monday and has exactly four weeks — no padding row either side.
    @Test func aMonthThatFitsFourRows() {
        let grid = MonthGrid(MonthKey(year: 2027, month: 2)!, in: tz)
        #expect(grid.weeks.count == 4)
        #expect(grid.weeks.first?.days.first?.dayKey == "2027-02-01")
        #expect(grid.weeks.last?.days.last?.dayKey == "2027-02-28")
    }

    /// August 2026 starts on a Saturday and needs six rows.
    @Test func aMonthThatNeedsSixRows() {
        let grid = MonthGrid(MonthKey(year: 2026, month: 8)!, in: tz)
        #expect(grid.weeks.count == 6)
        #expect(grid.weeks.first?.days.first?.dayKey == "2026-07-27")
        #expect(grid.weeks.last?.days.last?.dayKey == "2026-09-06")
    }

    /// The row spanning New Year belongs to one ISO week whichever month it is drawn in — the
    /// reason the epic highlight goes by `weekKey`, not by row position.
    @Test func theWeekAcrossNewYearHasOneKeyInBothMonths() {
        let dec = MonthGrid(MonthKey(year: 2026, month: 12)!, in: tz)
        let jan = MonthGrid(MonthKey(year: 2027, month: 1)!, in: tz)
        #expect(dec.weeks.last?.weekKey == "2026-W53")
        #expect(jan.weeks.first?.weekKey == "2026-W53")
        #expect(dec.weeks.last?.days == jan.weeks.first?.days.map {
            MonthGrid.Day(dayKey: $0.dayKey, dayOfMonth: $0.dayOfMonth, inMonth: $0.dayKey < "2027-01-01")
        })
    }
}
