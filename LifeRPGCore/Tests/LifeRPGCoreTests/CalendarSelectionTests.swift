import Testing
@testable import LifeRPGCore

/// `CalendarSelection` is what the workout-detection setting stores (`PLAN.md` §5). The storage
/// string is what `@AppStorage("workoutCalendarID")` already holds on installs that predate
/// multi-select, so those must keep reading as the one calendar they picked.
struct CalendarSelectionTests {
    @Test func containsFollowsTheCase() {
        #expect(!CalendarSelection.none.contains("a"))
        #expect(CalendarSelection.some(["a", "b"]).contains("a"))
        #expect(!CalendarSelection.some(["a", "b"]).contains("c"))
        #expect(CalendarSelection.all.contains("anything"))
    }

    @Test func aLegacySingleIDReadsAsThatCalendar() {
        #expect(CalendarSelection(setting: "8F2A-11") == .some(["8F2A-11"]))
    }

    @Test func emptyIsNoneAndStarIsAll() {
        #expect(CalendarSelection(setting: "") == .none)
        #expect(CalendarSelection(setting: "  ") == .none)
        #expect(CalendarSelection(setting: "*") == .all)
        #expect(CalendarSelection.none.setting == "")
        #expect(CalendarSelection.all.setting == "*")
    }

    @Test func severalIDsAreStoredSortedAndCommaSeparated() {
        #expect(CalendarSelection.some(["b", "a"]).setting == "a,b")
        #expect(CalendarSelection(setting: "b, a,,") == .some(["a", "b"]))
    }

    @Test func everyCaseSurvivesTheStorageRoundTrip() {
        for s in [CalendarSelection.none, .all, .some(["a"]), .some(["a", "b", "c"])] {
            #expect(CalendarSelection(setting: s.setting) == s)
        }
    }

    /// A selection that names nothing is `none`, so the two spellings of "no calendar" agree.
    @Test func anEmptySetIsStoredAsNone() {
        #expect(CalendarSelection.some([]).setting == "")
        #expect(CalendarSelection(setting: CalendarSelection.some([]).setting) == .none)
    }

    /// The storage format cannot hold a comma inside an ID, so such an ID is dropped rather than
    /// splitting into two phantom calendars.
    @Test func anIDWithACommaIsNotStored() {
        #expect(CalendarSelection.some(["a,b", "c"]).setting == "c")
        #expect(CalendarSelection.some(["a,b"]).setting == "")
    }

    @Test func togglingAddsAndRemovesOneCalendar() {
        #expect(CalendarSelection.none.toggling("a") == .some(["a"]))
        #expect(CalendarSelection.some(["a"]).toggling("b") == .some(["a", "b"]))
        #expect(CalendarSelection.some(["a", "b"]).toggling("a") == .some(["b"]))
        #expect(CalendarSelection.some(["a"]).toggling("a") == .none)
    }
}
