import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// From schema 9 the backup carries the whole library, because the library in the store is the
/// truth (the CSVs only start an empty one): every row with its id, its edits, its stamps and its
/// archived mark. A restore puts the rows back under those ids, so nothing the history points at
/// needs re-pointing. Files from before still restore the old way.
struct LibraryBackupTests {
    private let side = """
    text,difficulty,hidden_eligible,weekend_only,cooldown_days,auto_verify,launch_url,variants,is_active
    Seed quest A,E,FALSE,FALSE,,,,,TRUE
    Seed quest B,M,TRUE,FALSE,,,,,TRUE
    Seed epic,EPIC,FALSE,FALSE,,,,,TRUE
    """
    private let routineCSV = """
    text,frequency_kind,frequency_spec,weekly_target,base_points,difficulty,flexible_within_week,counts_for_clear,is_active,downgrade_of,auto_verify,launch_url,notes
    Seed routine,weekly,SAT,1,25,E,FALSE,TRUE,TRUE,,,,
    Seed walk,weekly,MON,1,15,E,FALSE,TRUE,TRUE,,,,
    Short walk,,,1,5,E,FALSE,TRUE,TRUE,Seed walk,,,
    """

    private func seeded() throws -> ModelContext {
        let ctx = try Fixtures.context()
        try SeedImporter.seedIfEmpty(ctx, sideQuestsCSV: side, routinesCSV: routineCSV)
        return ctx
    }

    private func quest(_ ctx: ModelContext, _ text: String) throws -> QuestTemplate {
        try #require(try ctx.fetch(FetchDescriptor<QuestTemplate>()).first { $0.text == text })
    }

    private func routine(_ ctx: ModelContext, _ text: String) throws -> RoutineTask {
        try #require(try ctx.fetch(FetchDescriptor<RoutineTask>()).first { $0.text == text })
    }

    private func restore(_ source: ModelContext, into target: ModelContext) throws {
        let plan = try JSONImport.plan(try JSONExport.data(source), against: target)
        try JSONImport.apply(plan, to: target)
    }

    /// A source store the user has been busy in: a rename, a tier change, new days, a deleted row,
    /// rows of their own, stamps from use.
    private func edited() throws -> ModelContext {
        let ctx = try seeded()
        let a = try quest(ctx, "Seed quest A")
        try LibraryEdit.rename("Seed quest A, reworded", .quest, id: a.id, in: ctx)
        try LibraryEdit.archive(.quest, id: try quest(ctx, "Seed quest B").id, in: ctx)
        let r = try routine(ctx, "Seed routine")
        try LibraryEdit.setDifficulty(.hard, forRoutine: r.id, in: ctx)
        var days = LibrarySave.Draft(); days.kind = .routine; days.days = [.tuesday, .friday]
        try LibraryEdit.setSchedule(days, forRoutine: r.id, in: ctx)
        try LibrarySave.saveQuest(text: "My epic", .init(difficulty: .epic), in: ctx)
        try LibrarySave.saveQuest(text: "My micro", .init(difficulty: .trivial, hiddenEligible: true), in: ctx)
        try LibrarySave.saveRoutine(text: "My piano", .init(difficulty: .medium, every: .weekly([.monday])), in: ctx)
        a.lastCompletedDayKey = "2026-09-20"; a.lastServedDayKey = "2026-09-21"; a.affinity = 1
        r.lastCompletedDayKey = "2026-09-19"
        try ctx.save()
        return ctx
    }

    // MARK: what is written

    @Test func theBackupIsSchemaElevenAndCarriesTheWholeLibrary() throws {
        let ctx = try edited()
        let s = try JSONExport.snapshot(ctx)
        #expect(JSONExport.schemaVersion == 11 && s.schemaVersion == 11)
        let full = try #require(s.fullLibrary)
        #expect(full.quests.count == (try ctx.fetchCount(FetchDescriptor<QuestTemplate>())))
        #expect(full.routines.count == (try ctx.fetchCount(FetchDescriptor<RoutineTask>())))
        let archived = try #require(full.quests.first { $0.text == "Seed quest B" })
        #expect(archived.isArchived && !archived.isActive)
        let mine = try #require(full.quests.first { $0.text == "My epic" })
        #expect(mine.origin == "user" && mine.difficulty == "epic")
        let a = try #require(full.quests.first { $0.text == "Seed quest A, reworded" })
        #expect(a.lastCompletedDayKey == "2026-09-20" && a.lastServedDayKey == "2026-09-21" && a.affinity == 1)
        let r = try #require(full.routines.first { $0.text == "Seed routine" })
        #expect(r.spec == "TUE,FRI" && r.difficulty == "hard" && r.basePoints == 38 && r.weeklyTarget == 2)
    }

    @Test func theOldLibraryBlocksAreNoLongerWritten() throws {
        let s = try JSONExport.snapshot(try edited())
        #expect(s.library == nil && s.userLibrary == nil && s.libraryChanges == nil)
    }

    /// Even a store with nothing in it says so, so import can tell a v9 file from an older one.
    @Test func anEmptyLibraryIsStillABlock() throws {
        let s = try JSONExport.snapshot(try Fixtures.context())
        #expect(s.fullLibrary?.quests.isEmpty == true && s.fullLibrary?.routines.isEmpty == true)
    }

    /// The backup is only the library if it holds every stored property of both models. A field added
    /// to `QuestTemplate` or `RoutineTask` and left out of `FullQuest` / `FullRoutine` would come back
    /// from a restore as its default, so this fails until the backup carries it.
    @Test func theBackupCarriesEveryStoredPropertyOfBothLibraryModels() throws {
        func keys(_ value: some Encodable) throws -> Set<String> {
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
            return Set(try #require(object as? [String: Any]).keys)
        }
        func stored(_ entity: String) throws -> Set<String> {
            Set(try #require(LifeRPGSchema.current.entities.first { $0.name == entity }).attributesByName.keys)
        }
        // The backup names three of these without the `Raw` / `String` the model stores them under.
        let renamed = ["difficulty": "difficultyRaw", "origin": "originRaw", "kind": "kindRaw",
                       "launchURL": "launchURLString"]

        let quest = JSONExport.FullQuest(
            id: UUID(), text: "", difficulty: "", hiddenEligible: false, weekendOnly: false,
            cooldownDaysOverride: 1, variants: [], launchURL: "", autoVerifyRule: "", affinity: 0,
            lastServedDayKey: "", lastCompletedDayKey: "", isActive: true, isArchived: false, origin: "",
            starterKey: "")
        #expect(Set(try keys(quest).map { renamed[$0] ?? $0 }) == (try stored("QuestTemplate")))

        let routine = JSONExport.FullRoutine(
            id: UUID(), text: "", difficulty: "", basePoints: 0, kind: "", spec: "", anchorWeekKey: "",
            weeklyTarget: 1, flexibleWithinWeek: false, countsForClear: true, downgradeIDs: [], launchURL: "",
            autoVerifyRule: "", lastCompletedDayKey: "", isActive: true, isArchived: false, origin: "",
            starterKey: "")
        #expect(Set(try keys(routine).map { renamed[$0] ?? $0 }) == (try stored("RoutineTask")))
    }

    @Test func theStarterKeyComesBackWithTheRow() throws {
        let source = try seeded()
        try quest(source, "Seed quest A").starterKey = "seed-a"
        try routine(source, "Seed routine").starterKey = "seed-r"
        try source.save()
        let target = try seeded()
        try restore(source, into: target)
        #expect(try quest(target, "Seed quest A").starterKey == "seed-a")
        #expect(try routine(target, "Seed routine").starterKey == "seed-r")
    }

    // MARK: a reinstall

    @Test func aReinstallGetsEveryRowBackUnderItsOwnId() throws {
        let source = try edited()
        let target = try seeded()                                             // a fresh install: new UUIDs
        try restore(source, into: target)

        func rows(_ c: ModelContext) throws -> [String] {
            try c.fetch(FetchDescriptor<QuestTemplate>()).map {
                "\($0.id)|\($0.text)|\($0.difficultyRaw)|\($0.isActive)|\($0.isArchived)|\($0.originRaw)|\($0.hiddenEligible)"
            }.sorted() + c.fetch(FetchDescriptor<RoutineTask>()).map {
                "\($0.id)|\($0.text)|\($0.difficultyRaw)|\($0.basePoints)|\($0.spec)|\($0.isActive)|\($0.isArchived)|\($0.originRaw)|\($0.downgradeIDs)"
            }.sorted()
        }
        #expect(try rows(target) == rows(source))
        #expect(try StoreAudit.issues(target).isEmpty)
    }

    /// The thing the old way could not do: a renamed seed row is neither duplicated nor lost.
    @Test func aRenamedRowIsNotDuplicatedAndADeletedOneStaysArchived() throws {
        let source = try edited()
        let target = try seeded()
        try restore(source, into: target)
        let texts = try target.fetch(FetchDescriptor<QuestTemplate>()).map(\.text)
        #expect(texts.filter { $0.hasPrefix("Seed quest A") } == ["Seed quest A, reworded"])
        #expect(try quest(target, "Seed quest B").isArchived)
        #expect(texts.count == (try source.fetchCount(FetchDescriptor<QuestTemplate>())))
    }

    @Test func theStampsComeBackWithTheRows() throws {
        let source = try edited()
        let target = try seeded()
        try restore(source, into: target)
        let a = try quest(target, "Seed quest A, reworded")
        #expect(a.lastCompletedDayKey == "2026-09-20" && a.lastServedDayKey == "2026-09-21")
        #expect(try routine(target, "Seed routine").lastCompletedDayKey == "2026-09-19")
    }

    /// History holds ids, and the ids are the ones the restored rows have: a rating given to a row
    /// that was renamed, and an occurrence of a routine that was deleted, still resolve.
    @Test func historyStillPointsAtTheRestoredRows() throws {
        let source = try edited()
        let renamed = try quest(source, "Seed quest A, reworded")
        let gone = try routine(source, "Seed walk")
        try LibraryEdit.archive(.routine, id: gone.id, in: source)
        let o = RoutineOccurrence(routine: gone, dueDayKey: "2026-09-21", weekKey: "2026-W39")
        source.insert(o)
        let rating = QuestRating()
        rating.targetID = renamed.id; rating.targetKindRaw = FeedbackTarget.quest.rawValue
        rating.textSnapshot = "Seed quest A"; rating.rating = 2; rating.dayKey = "2026-09-21"
        source.insert(rating)
        try source.save()

        let target = try seeded()
        try restore(source, into: target)
        let back = try target.fetch(FetchDescriptor<RoutineOccurrence>())
        #expect(back.first?.routineID == gone.id)
        #expect(try target.fetch(FetchDescriptor<RoutineTask>()).contains { $0.id == gone.id && $0.isArchived })
        let r = try #require(try target.fetch(FetchDescriptor<QuestRating>()).first)
        #expect(r.targetID == renamed.id && r.textSnapshot == "Seed quest A")
        #expect(try target.fetch(FetchDescriptor<QuestTemplate>()).contains { $0.id == renamed.id })
    }

    @Test func theSummaryCountsTheLibrary() throws {
        let source = try edited()
        let plan = try JSONImport.plan(try JSONExport.data(source), against: try seeded())
        #expect(plan.summary.libraryQuests == (try source.fetchCount(FetchDescriptor<QuestTemplate>())))
        #expect(plan.summary.libraryRoutines == (try source.fetchCount(FetchDescriptor<RoutineTask>())))
        #expect(plan.summary.libraryArchived == 1)
        #expect(plan.summary.unmatchedLibrary.isEmpty)
    }

    /// A restore is wholesale for the library too: a row only the target has does not survive it.
    @Test func aRowOnlyTheTargetHasIsReplaced() throws {
        let source = try seeded()
        let target = try seeded()
        try LibrarySave.saveQuest(text: "Only on the target", .init(difficulty: .easy), in: target)
        try restore(source, into: target)
        #expect(try target.fetch(FetchDescriptor<QuestTemplate>()).allSatisfy { $0.text != "Only on the target" })
    }

    // MARK: versions

    @Test func aNewerFileIsRefusedAndAnOlderOneStillReads() throws {
        let source = try seeded()
        var s = try JSONExport.snapshot(source)
        s.schemaVersion = 12
        #expect(throws: JSONImport.Failure.newerExport(12)) {
            try JSONImport.plan(try JSONExport.encode(s), against: try seeded())
        }
        #expect(JSONExport.oldestReadableVersion == 3)
    }

    /// A file written by the build before this one: the library is re-pointed by text, the user's
    /// own rows are put back, and what was changed on the seed rows is re-applied.
    @Test func aSchemaEightFileStillRestoresTheOldWay() throws {
        let source = try seeded()
        try LibraryEdit.setActive(false, .quest, id: try quest(source, "Seed quest A").id, in: source)
        try LibrarySave.saveQuest(text: "My epic", .init(difficulty: .epic), in: source)
        let rating = QuestRating()
        rating.targetID = try quest(source, "Seed quest A").id; rating.targetKindRaw = FeedbackTarget.quest.rawValue
        rating.textSnapshot = "Seed quest A"; rating.rating = 1; rating.dayKey = "2026-09-20"
        source.insert(rating)
        try source.save()
        let file = try LegacyBackup.data(source, sideQuestsCSV: side, routinesCSV: routineCSV)

        let target = try seeded()                                             // reseeded: different UUIDs
        let plan = try JSONImport.plan(file, against: target)
        #expect(plan.summary.libraryChanges == 1 && plan.summary.userQuests == 1)
        try JSONImport.apply(plan, to: target)

        let a = try quest(target, "Seed quest A")
        #expect(!a.isActive)
        #expect(try quest(target, "My epic").difficulty == .epic)
        #expect(try target.fetch(FetchDescriptor<QuestRating>()).first?.targetID == a.id)
    }
}
