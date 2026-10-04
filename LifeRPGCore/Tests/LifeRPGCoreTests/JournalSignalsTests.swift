import Foundation
import Testing
@testable import LifeRPGCore

struct JournalSignalsTests {
    typealias F = JournalFixtures

    @Test func choiceItemsAreRecognisedByTheirKeywords() {
        let choice = ["Take a PHOTO of the sky", "Photograph a set of things in a given color", "Make a picture with AI",
                      "Pick a book from the shelf", "Choose a song for tomorrow", "Notice three green things",
                      "Look at photos from this day last year", "Look at the moon for a minute"]
        let plain = ["Drink 2L of water", "Stretch for 10 minutes", "Go for a walk"]
        for text in choice { #expect(JournalSignals.isChoice(text), "\(text)") }
        for text in plain { #expect(!JournalSignals.isChoice(text), "\(text)") }
        #expect(JournalSignals.isPhoto("Take a photo of the sky"))
        #expect(!JournalSignals.isPhoto("Pick a book"))
    }

    @Test func completedCountAndAverageComeFromTheDaysRowsOnly() {
        let a = F.quest("Walk"), b = F.quest("Read"), open = F.quest("Stretch", done: false)
        let elsewhere = F.quest("Yesterday's", on: "2026-09-17")
        let routine = F.routineDone("Take out the trash")
        let signals = F.signals(quests: [a, b, open, elsewhere], occurrences: [routine],
                                ratings: [F.rating(of: a.id, 2), F.rating(of: b.id, -1), F.rating(of: routine.id, 1)])
        #expect(signals.completedCount == 3)
        // (2 - 1 + 1) / 3
        #expect(signals.averageRating == 2.0 / 3.0)
        #expect(signals.tier == .normal)
    }

    @Test func aRatingWithNoCompletionBehindItSaysNothingAboutTheDay() {
        let a = F.quest("Walk")
        let signals = F.signals(quests: [a], ratings: [F.rating(of: UUID(), -2)])
        #expect(signals.averageRating == nil)
        #expect(signals.completed.first?.rating == nil)
    }

    @Test func theNewestRatingOfACompletionWins() {
        let a = F.quest("Walk")
        let signals = F.signals(quests: [a], ratings: [F.rating(of: a.id, -2, hour: 12), F.rating(of: a.id, 1, hour: 13)])
        #expect(signals.completed.first?.rating == 1)
    }

    @Test func replacedRowsAreIgnoredEverywhere() {
        let swapped = F.quest("Swapped away", replaced: true)
        let photo = F.quest("Take a photo", replaced: true)
        let routine = F.routineDone("Replaced routine")
        routine.replacedByID = UUID()
        let signals = F.signals(quests: [swapped, photo], occurrences: [routine],
                                ratings: [F.rating(of: swapped.id, 2), F.rating(of: photo.id, 2)])
        #expect(signals.completedCount == 0)
        #expect(signals.averageRating == nil)
        #expect(signals.bestRated == nil)
        #expect(signals.choiceItem == nil)
    }

    @Test func theBestRatedIsTheHighestAndTheLatestWinsATie() {
        let early = F.quest("Early", hour: 8), late = F.quest("Late", hour: 18), top = F.quest("Top", hour: 9)
        let low = F.quest("Low", hour: 19)
        let signals = F.signals(quests: [early, late, top, low],
                                ratings: [F.rating(of: early.id, 1), F.rating(of: late.id, 2),
                                          F.rating(of: top.id, 2), F.rating(of: low.id, 0)])
        #expect(signals.bestRated?.subject.text == "Late")
        let onlyOnes = F.signals(quests: [early, late], ratings: [F.rating(of: early.id, 1), F.rating(of: late.id, 1)])
        #expect(onlyOnes.bestRated?.subject.text == "Late")
        let none = F.signals(quests: [low], ratings: [F.rating(of: low.id, 0)])
        #expect(none.bestRated == nil)
    }

    /// A photo quest is asked about as a choice, so it can't also be the "good moment".
    @Test func aChoiceItemIsNeverTheBestRatedOne() {
        let photo = F.quest("Take a photo of the sky")
        let signals = F.signals(quests: [photo], ratings: [F.rating(of: photo.id, 2)])
        #expect(signals.bestRated == nil)
        #expect(signals.choiceItem?.subject.text == "Take a photo of the sky")
        #expect(signals.choiceItem?.rating == 2)
    }

    @Test func aRoutineOnItsLightVersionIsNamedByTheVersionDone() {
        let o = F.routineDone("Strength session")
        o.usedDegraded = true
        o.degradedTextSnapshot = "A 30 minute walk"
        let signals = F.signals(occurrences: [o])
        #expect(signals.completed.map(\.subject.text) == ["A 30 minute walk"])
        #expect(signals.completed.first?.subject.kind == .routine)
    }

    // MARK: routines to ask about without blame

    @Test func anOpenRoutineIsAskedAboutOnlyOnceItIsOverdue() {
        let today = F.occurrence("Due today", due: "2026-09-18")
        let round2 = F.occurrence("Round two", due: "2026-09-17")
        let round3 = F.occurrence("Round three", due: "2026-09-16")
        let future = F.occurrence("Due tomorrow", due: "2026-09-19")
        let signals = F.signals(occurrences: [today, round2, round3, future])
        // Most recently due first.
        #expect(signals.skipped.map(\.text) == ["Round two", "Round three"])
        #expect(signals.skipped.allSatisfy { $0.kind == .routine })
    }

    @Test func aRoutineTheSettlementGaveUpOnThisMorningIsAskedAbout() {
        let missed = F.occurrence("Auto skipped", due: "2026-09-15", skipped: true)
        let oldMiss = F.occurrence("Missed last week", due: "2026-09-08", skipped: true)
        let signals = F.signals(occurrences: [missed, oldMiss],
                                ledger: [F.skipEntry(for: missed, on: "2026-09-18"),
                                         F.skipEntry(for: oldMiss, on: "2026-09-12")])
        #expect(signals.skipped.map(\.text) == ["Auto skipped"])
    }

    @Test func aRoutineYouCancelledSwappedOrDidIsNeverAskedAbout() {
        let cancelled = F.occurrence("Paid to cancel", due: "2026-09-16", skipped: true)
        let swapped = F.occurrence("Swapped", due: "2026-09-16")
        swapped.replacedByID = UUID()
        let done = F.occurrence("Made up", due: "2026-09-16", completed: "2026-09-18")
        let signals = F.signals(occurrences: [cancelled, swapped, done])
        #expect(signals.skipped.isEmpty)
    }

    @Test func aFlexibleRoutineHasNoOverdueLadder() {
        let routineID = UUID()
        let flexible = F.occurrence("Gym session", due: "2026-09-16", routineID: routineID)
        #expect(F.signals(occurrences: [flexible]).skipped.map(\.text) == ["Gym session"])
        #expect(F.signals(occurrences: [flexible], flexible: [routineID]).skipped.isEmpty)
    }

    @Test func commentsAreTheDaysOwnInOrder() {
        func note(_ text: String, _ day: String, hour: Int) -> QuestComment {
            let c = QuestComment()
            c.comment = text; c.dayKey = day; c.timestamp = Fixtures.date(day, hour: hour)
            return c
        }
        let signals = JournalSignals(dayKey: F.day, quests: [], occurrences: [], context: nil, ratings: [],
                                     comments: [note("later", F.day, hour: 20), note("other day", "2026-09-17", hour: 9),
                                                note("earlier", F.day, hour: 8)])
        #expect(signals.comments == ["earlier", "later"])
        #expect(signals.tier == .normal)
    }
}
