import Foundation
import Testing
@testable import LifeRPGCore

struct JournalPoolTests {
    @Test func languageFollowsTheFirstPreferredLanguage() {
        let cases: [([String], JournalLanguage)] = [
            (["zh-Hans-CN", "en-US"], .zhHans),
            (["zh-Hans"], .zhHans),
            (["zh"], .zhHans),
            (["zh-CN"], .zhHans),
            (["zh_SG"], .zhHans),
            (["zh-Hant-TW"], .en),
            (["zh-HK"], .en),
            (["en-US", "zh-Hans-CN"], .en),
            (["fr-FR"], .en),
            ([], .en),
        ]
        for (preferred, expected) in cases {
            #expect(JournalLanguage.resolve(preferred: preferred) == expected, "\(preferred)")
        }
    }

    @Test func thePoolHasTheRowsOfTheDraft() {
        let counts = Dictionary(grouping: JournalPool.all, by: \.kind).mapValues(\.count)
        #expect(counts == [.opening: 3, .heavy: 4, .good: 3, .choice: 3, .skip: 3,
                           .followUp: 3, .closing: 2, .safety: 1])
        #expect(Set(JournalPool.all.map(\.id)).count == JournalPool.all.count)
    }

    /// The shape each row borrows, from the "Question shapes" paragraph of the draft: scaling and
    /// open questions, self-compassion, savoring, values, exceptions, reflective listening.
    @Test func everyRowCarriesTheShapeItBorrows() {
        let expected: [String: JournalApproach] = [
            "open.scale": .scale, "open.feel": .open, "open.keep": .savoring,
            "heavy.done": .selfCompassion, "heavy.weight": .open, "heavy.friend": .selfCompassion,
            "heavy.body": .selfCompassion,
            "good.moment": .savoring, "good.repeat": .values, "good.who": .savoring,
            "choice.photo": .savoring, "choice.item": .values, "choice.notice": .savoring,
            "skip.block": .open, "skip.exception": .exceptions, "skip.small": .exceptions,
            "follow.stand": .reflection, "follow.more": .reflection, "follow.need": .reflection,
            "close.more": .open, "close.carry": .values, "safety": .open,
        ]
        #expect(Dictionary(uniqueKeysWithValues: JournalPool.all.map { ($0.id, $0.approach) }) == expected)
    }

    @Test func bothLanguagesAskForTheSamePlaceholders() {
        for row in JournalPool.all {
            #expect(JournalPool.placeholders(in: row.en) == JournalPool.placeholders(in: row.zh), "\(row.id)")
        }
    }

    /// The draft is what the user edits; the code table has to be the same words. Skipped where the
    /// draft isn't checked in yet.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: Fixtures.docDir.appendingPathComponent("JOURNAL_PROMPTS.md").path)))
    func theTableMatchesTheDraftRowForRow() throws {
        let doc = try Fixtures.csv("JOURNAL_PROMPTS.md")
        var rows: [(id: String, en: String, zh: String)] = []
        for line in doc.split(separator: "\n") where line.hasPrefix("| ") {
            let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                .dropFirst().dropLast().map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count == 3, cells[0] != "id", !cells[0].hasPrefix("---") else { continue }
            rows.append((cells[0], cells[1], cells[2]))
        }
        #expect(rows.map(\.id) == JournalPool.all.map(\.id))
        for (row, prompt) in zip(rows, JournalPool.all) {
            #expect(row.en == prompt.en, "\(row.id) en")
            #expect(row.zh == prompt.zh, "\(row.id) zh")
        }
    }

    @Test func rendersAFilledRowInEitherLanguage() {
        #expect(JournalPool.render(id: "good.moment", language: .en, fills: [.quest: "Morning run"])
                == "You rated Morning run high. Which moment was the best part?")
        #expect(JournalPool.render(id: "good.moment", language: .zhHans, fills: [.quest: "晨跑"])
                == "你给「晨跑」打了高分。哪一刻最好？")
        #expect(JournalPool.render(id: "choice.item", language: .en, fills: [.item: "Red"])
                == "You picked Red. What made it the one?")
        #expect(JournalPool.render(id: "open.keep", language: .en) == "What from today do you want to remember?")
    }

    /// A raw `{quest}` on screen is the failure; a missing or blank fill must give nil instead.
    @Test func aMissingOrBlankFillIsNilNeverARawPlaceholder() {
        #expect(JournalPool.render(id: "skip.block", language: .en) == nil)
        #expect(JournalPool.render(id: "skip.block", language: .en, fills: [.item: "x"]) == nil)
        #expect(JournalPool.render(id: "skip.block", language: .zhHans, fills: [.quest: "  "]) == nil)
        #expect(JournalPool.render(id: "no.such.row", language: .en) == nil)
        for language in JournalLanguage.allCases {
            for row in JournalPool.all where !JournalPool.placeholders(in: row.text(in: language)).isEmpty {
                #expect(JournalPool.render(id: row.id, language: language) == nil, "\(row.id)")
            }
        }
    }

    @Test func aFillThatLooksLikeAPlaceholderIsInsertedAsText() {
        #expect(JournalPool.render(id: "skip.block", language: .en, fills: [.quest: "{phrase} run"])
                == "{phrase} run didn't happen. What got in the way?")
    }
}
