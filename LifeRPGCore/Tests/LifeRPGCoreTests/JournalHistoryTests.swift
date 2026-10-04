import Foundation
import Testing
@testable import LifeRPGCore

struct JournalHistoryTests {
    typealias F = JournalFixtures

    private func days(_ turns: [JournalTurn]) -> [JournalDay] {
        JournalHistory.days(from: turns, language: .en)
    }

    @Test func daysComeNewestFirstWhateverOrderTheTurnsArriveIn() {
        let turns = [
            F.turn(.opening, "b", index: 0, on: "2026-09-17"),
            F.turn(.opening, "c", index: 0, on: "2026-09-19"),
            F.turn(.opening, "a", index: 0, on: "2026-09-02"),
            F.turn(.good, "d", index: 1, on: "2026-09-19"),
        ]
        #expect(days(turns).map(\.dayKey) == ["2026-09-19", "2026-09-17", "2026-09-02"])
        #expect(days(turns).map(\.answeredCount) == [2, 1, 1])
    }

    @Test func aDayWithOnlySkippedMisfitSafetyOrBlankTurnsIsOmitted() {
        let turns = [
            F.turn(.opening, "", index: 0, on: "2026-09-17", outcome: .skipped),
            F.turn(.heavy, "left over", index: 1, on: "2026-09-17", outcome: .misfit),
            F.turn(.safety, "ok", index: 2, on: "2026-09-17"),
            F.turn(.opening, "  ", index: 0, on: "2026-09-18"),
            F.turn(.opening, "kept", index: 0, on: "2026-09-19"),
        ]
        #expect(days(turns).map(\.dayKey) == ["2026-09-19"])
    }

    @Test func aDayKeepsItsSkippedTurnsInIndexOrderButNotTheSafetyLine() throws {
        let turns = [
            F.turn(.closing, "bye", index: 3),
            F.turn(.safety, "line", index: 2),
            F.turn(.heavy, "", index: 1, outcome: .skipped),
            F.turn(.opening, "hello there", index: 0),
        ]
        let day = try #require(days(turns).first)
        #expect(day.turns.map(\.index) == [0, 1, 3])
        #expect(day.answeredCount == 2)
        #expect(day.preview == "hello there")
    }

    @Test func thePreviewIsTheFirstAnswerOnOneLine() throws {
        let turns = [
            F.turn(.opening, "", index: 0, outcome: .skipped),
            F.turn(.good, "the  walk\n\nhome,\t in the rain ", index: 1),
            F.turn(.closing, "later", index: 2),
        ]
        #expect(try #require(days(turns).first).preview == "the walk home, in the rain")
    }

    @Test func thePreviewIsCutAtEightyCharactersWithAnEllipsisOnlyWhenCut() throws {
        func preview(_ count: Int) throws -> String {
            try #require(days([F.turn(.opening, String(repeating: "a", count: count))]).first).preview
        }
        #expect(try preview(79) == String(repeating: "a", count: 79))
        #expect(try preview(80) == String(repeating: "a", count: 80))
        #expect(try preview(81) == String(repeating: "a", count: 80) + "…")
    }

    @Test func theCutCountsCharactersAfterWhitespaceIsCollapsed() throws {
        // 40 + 3 spaces + 40 collapses to 81 characters, so it is cut; 40 + 1 space + 39 is 80 and is not.
        let long = String(repeating: "a", count: 40) + "   " + String(repeating: "b", count: 40)
        #expect(try #require(days([F.turn(.opening, long)]).first).preview
                == String(repeating: "a", count: 40) + " " + String(repeating: "b", count: 39) + "…")
        let exact = String(repeating: "a", count: 40) + "   " + String(repeating: "b", count: 39)
        #expect(try #require(days([F.turn(.opening, exact)]).first).preview
                == String(repeating: "a", count: 40) + " " + String(repeating: "b", count: 39))
    }

    @Test func aChineseAnswerIsCutByCharacterNotByByte() throws {
        let preview = try #require(days([F.turn(.opening, String(repeating: "字", count: 81))]).first).preview
        #expect(preview == String(repeating: "字", count: 80) + "…")
    }

    @Test func isClosedAndTextFollowTheProgressAndComposerRules() throws {
        let open = [F.turn(.opening, "hello", index: 0)]
        let closed = open + [F.turn(.closing, "bye", index: 1)]
        let day = try #require(days(open).first)
        #expect(!day.isClosed)
        #expect(day.text == JournalComposer.text(turns: open, language: .en))
        #expect(day.text == "Journal 2026-09-18\n\nquestion\nhello")
        #expect(try #require(days(closed).first).isClosed)
        #expect(JournalHistory.days(from: closed, language: .zhHans).first?.text.hasPrefix("日记 2026-09-18") == true)
    }

    @Test func noTurnsIsNoDays() {
        #expect(days([]).isEmpty)
    }
}
