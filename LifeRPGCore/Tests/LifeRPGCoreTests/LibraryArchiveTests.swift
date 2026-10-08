import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// Renaming a library row and deleting it. Both leave the row's id alone, because what the history,
/// the ratings and the notes hold is that id (and a text snapshot of their own): a rename changes
/// what the Library calls the row, and a delete is an archive — the row stays, unlisted, so
/// nothing that pointed at it stops resolving.
struct LibraryArchiveTests {
    private let tz = Fixtures.tokyo
    private let friday = "2026-09-18"

    private func routine(_ ctx: ModelContext, _ text: String = "Piano", spec: String = "FRI") -> RoutineTask {
        let r = RoutineTask()
        r.text = text; r.kind = .weekly; r.spec = spec
        ctx.insert(r)
        return r
    }

    // MARK: renaming

    @Test func aRenameKeepsTheIdAndOnlyChangesTheWords() throws {
        let ctx = try Fixtures.context()
        let q = Fixtures.quest(ctx, "Sing a song out loud at home")
        let r = routine(ctx)
        try ctx.save()
        let (qid, rid) = (q.id, r.id)

        try LibraryEdit.rename("  Sing in the shower \n", .quest, id: q.id, in: ctx)
        try LibraryEdit.rename("Practise piano", .routine, id: r.id, in: ctx)
        #expect(q.text == "Sing in the shower" && q.id == qid)
        #expect(r.text == "Practise piano" && r.id == rid)
    }

    /// The history says what it said when it happened.
    @Test func theHistoryKeepsTheWordsItWasMadeWith() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx)
        let o = RoutineOccurrence(routine: r, dueDayKey: friday, weekKey: "2026-W38")
        ctx.insert(o)
        let rating = QuestRating()
        rating.targetID = r.id; rating.targetKindRaw = FeedbackTarget.routine.rawValue
        rating.textSnapshot = "Piano"; rating.rating = 2
        ctx.insert(rating)
        try ctx.save()

        try LibraryEdit.rename("Practise piano", .routine, id: r.id, in: ctx)
        #expect(o.textSnapshot == "Piano" && o.routineID == r.id)
        #expect(rating.textSnapshot == "Piano" && rating.targetID == r.id)
    }

    @Test func aRenameNeedsWordsAndAFreeName() throws {
        let ctx = try Fixtures.context()
        let a = Fixtures.quest(ctx, "Sing a song out loud at home")
        Fixtures.quest(ctx, "Draw something")
        try ctx.save()
        #expect(throws: LibraryEdit.Failure.emptyText) {
            try LibraryEdit.rename("   ", .quest, id: a.id, in: ctx)
        }
        #expect(throws: LibraryEdit.Failure.textTaken) {
            try LibraryEdit.rename("draw SOMETHING", .quest, id: a.id, in: ctx)
        }
        #expect(a.text == "Sing a song out loud at home")
        // Its own words, in another case, are still its own.
        try LibraryEdit.rename("sing a song out loud at home", .quest, id: a.id, in: ctx)
        #expect(a.text == "sing a song out loud at home")
    }

    @Test func aQuestAndARoutineMayShareWords() throws {
        let ctx = try Fixtures.context()
        Fixtures.quest(ctx, "Walk")
        let r = routine(ctx, "Run")
        try ctx.save()
        try LibraryEdit.rename("Walk", .routine, id: r.id, in: ctx)
        #expect(r.text == "Walk")
    }

    /// An archived row is out of the Library, so its words are free again.
    @Test func anArchivedRowDoesNotHoldItsWords() throws {
        let ctx = try Fixtures.context()
        let old = Fixtures.quest(ctx, "Draw something")
        let other = Fixtures.quest(ctx, "Sketch")
        try ctx.save()
        try LibraryEdit.archive(.quest, id: old.id, in: ctx)
        try LibraryEdit.rename("Draw something", .quest, id: other.id, in: ctx)
        #expect(other.text == "Draw something")
        // ...and once that one is archived too, the words are free for a new row as well.
        try LibraryEdit.archive(.quest, id: other.id, in: ctx)
        _ = try LibrarySave.saveQuest(text: "draw something ", .init(difficulty: .easy), in: ctx)
    }

    @Test func aRowThatIsGoneCannotBeRenamed() throws {
        let ctx = try Fixtures.context()
        #expect(throws: LibraryEdit.Failure.notFound) {
            try LibraryEdit.rename("x", .routine, id: UUID(), in: ctx)
        }
    }

    // MARK: archiving

    @Test func anArchivedRowIsInactiveToo() throws {
        let ctx = try Fixtures.context()
        let q = Fixtures.quest(ctx, "Sing a song out loud at home")
        let r = routine(ctx)
        try ctx.save()
        try LibraryEdit.archive(.quest, id: q.id, in: ctx)
        try LibraryEdit.archive(.routine, id: r.id, in: ctx)
        #expect(q.isArchived && !q.isActive)
        #expect(r.isArchived && !r.isActive)
    }

    /// Nothing that draws, schedules or offers a row sees an archived one: they all ask `isActive`.
    @Test func anArchivedRowIsNeverDrawnScheduledOrOffered() throws {
        let ctx = try Fixtures.context()
        let q = Fixtures.quest(ctx, "Sing a song out loud at home")
        let epic = Fixtures.quest(ctx, "Write a short story", .epic)
        let other = Fixtures.quest(ctx, "Another epic", .epic)
        let r = routine(ctx)
        try ctx.save()
        #expect(!AdHoc.libraryCandidates([r], occurrences: [], on: friday).isEmpty)
        #expect(!Schedule.dueRoutines([r], occurrences: [], on: friday, in: tz).isEmpty)

        for (target, id) in [(FeedbackTarget.quest, q.id), (.quest, epic.id), (.routine, r.id)] {
            try LibraryEdit.archive(target, id: id, in: ctx)
        }
        #expect(try Sampling.activeTemplates(ctx).map(\.id) == [other.id])
        #expect(AdHoc.libraryCandidates([r], occurrences: [], on: friday).isEmpty)
        #expect(Schedule.dueRoutines([r], occurrences: [], on: friday, in: tz).isEmpty)
    }

    /// Like turning a row off, it reaches forward only: what is on the page keeps running.
    @Test func whatIsAlreadyOnThePageIsLeftAlone() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx)
        let o = RoutineOccurrence(routine: r, dueDayKey: friday, weekKey: "2026-W38")
        ctx.insert(o)
        try ctx.save()
        try LibraryEdit.archive(.routine, id: r.id, in: ctx)
        #expect(Schedule.isOpen(o) && !o.skipped && o.routineID == r.id)
        // ...and the ladder still charges it, because the settlement reads the occurrence.
        try Overdue.settle(friday, in: ctx, timeZone: tz)
        #expect(o.penaltyApplied > 0)
    }

    @Test func archivingTwiceChangesNothing() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx)
        try ctx.save()
        try LibraryEdit.archive(.routine, id: r.id, in: ctx)
        try LibraryEdit.archive(.routine, id: r.id, in: ctx)
        #expect(r.isArchived && !r.isActive)
    }

    @Test func anArchivedRowCannotJustBeTurnedOn() throws {
        let ctx = try Fixtures.context()
        let q = Fixtures.quest(ctx, "Sing a song out loud at home")
        try ctx.save()
        try LibraryEdit.archive(.quest, id: q.id, in: ctx)
        #expect(throws: LibraryEdit.Failure.archived) {
            try LibraryEdit.setActive(true, .quest, id: q.id, in: ctx)
        }
        #expect(!q.isActive && q.isArchived)
    }

    @Test func aRowThatIsGoneCannotBeArchivedOrRestored() throws {
        let ctx = try Fixtures.context()
        #expect(throws: LibraryEdit.Failure.notFound) { try LibraryEdit.archive(.quest, id: UUID(), in: ctx) }
        #expect(throws: LibraryEdit.Failure.notFound) { try LibraryEdit.restore(.routine, id: UUID(), in: ctx) }
    }

    // MARK: restoring

    @Test func restoringBringsTheRowBackAsItWas() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx)
        r.difficulty = .hard; r.basePoints = 38
        try ctx.save()
        let id = r.id
        try LibraryEdit.archive(.routine, id: r.id, in: ctx)
        try LibraryEdit.restore(.routine, id: r.id, in: ctx)
        #expect(!r.isArchived && r.isActive && r.id == id && r.difficulty == .hard && r.basePoints == 38)
        #expect(!Schedule.dueRoutines([r], occurrences: [], on: friday, in: tz).isEmpty)
    }

    /// Restoring a row that was never archived is not a way to turn a row back on.
    @Test func restoringARowThatIsOnlyOffLeavesItOff() throws {
        let ctx = try Fixtures.context()
        let q = Fixtures.quest(ctx, "Sing a song out loud at home")
        try ctx.save()
        try LibraryEdit.setActive(false, .quest, id: q.id, in: ctx)
        try LibraryEdit.restore(.quest, id: q.id, in: ctx)
        #expect(!q.isActive && !q.isArchived)
    }

    // MARK: a routine's lighter versions

    private func family(_ ctx: ModelContext) -> (parent: RoutineTask, other: RoutineTask, light: RoutineTask, shared: RoutineTask) {
        let parent = routine(ctx, "Walk, 45 minutes")
        let other = routine(ctx, "Run, 20 minutes")
        let light = routine(ctx, "Short walk", spec: "")
        let shared = routine(ctx, "Stretch", spec: "")
        parent.downgradeIDs = [light.id, shared.id]
        other.downgradeIDs = [shared.id]
        return (parent, other, light, shared)
    }

    /// A lighter version is only ever reached through its routine, so one left with no routine to
    /// belong to goes with it; one another live routine still offers stays.
    @Test func archivingARoutineTakesItsOrphanedLighterVersionsWithIt() throws {
        let ctx = try Fixtures.context()
        let f = family(ctx)
        try ctx.save()
        try LibraryEdit.archive(.routine, id: f.parent.id, in: ctx)
        #expect(f.parent.isArchived && f.light.isArchived)
        #expect(!f.shared.isArchived && f.shared.isActive)           // `other` still offers it
        #expect(!f.other.isArchived)
    }

    @Test func archivingALighterVersionLeavesItsRoutineAlone() throws {
        let ctx = try Fixtures.context()
        let f = family(ctx)
        try ctx.save()
        try LibraryEdit.archive(.routine, id: f.light.id, in: ctx)
        #expect(f.light.isArchived && !f.parent.isArchived)
        #expect(Degrade.versions(of: f.parent, in: [f.parent, f.light, f.shared]).map(\.id) == [f.shared.id])
    }

    @Test func restoringARoutineBringsBackItsArchivedLighterVersions() throws {
        let ctx = try Fixtures.context()
        let f = family(ctx)
        try ctx.save()
        try LibraryEdit.archive(.routine, id: f.parent.id, in: ctx)
        try LibraryEdit.restore(.routine, id: f.parent.id, in: ctx)
        #expect(!f.parent.isArchived && !f.light.isArchived && f.light.isActive)
        #expect(Degrade.versions(of: f.parent, in: [f.parent, f.light, f.shared]).count == 2)
    }

    // MARK: what the Library lists

    @Test func theLibraryListsOnlyRowsThatAreNotArchived() throws {
        let ctx = try Fixtures.context()
        let a = Fixtures.quest(ctx, "Sing a song out loud at home")
        let b = Fixtures.quest(ctx, "Draw something")
        try ctx.save()
        try LibraryEdit.archive(.quest, id: b.id, in: ctx)
        let rows = try ctx.fetch(FetchDescriptor<QuestTemplate>())
        #expect(LibraryEdit.listed(rows).map(\.id) == [a.id])
        #expect(LibraryEdit.archived(rows).map(\.id) == [b.id])
    }
}
