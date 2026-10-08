import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

struct SeedImporterTests {
    private func makeContext() throws -> ModelContext {
        try Fixtures.context()
    }

    @discardableResult
    private func merge(_ ctx: ModelContext,
                       side: String? = nil,
                       routines: String? = nil) throws -> SeedImporter.Result {
        try SeedImporter.seedIfEmpty(ctx,
                                     sideQuestsCSV: side ?? Fixtures.csv("side_quests.csv"),
                                     routinesCSV: routines ?? Fixtures.csv("routine_quests.csv"))
    }

    /// Guards the schema declaration: a model missing from `SchemaV10.models` fails here.
    @Test func containerOpensWithVersionedSchema() throws {
        let ctx = try makeContext()
        #expect(SchemaV10.versionIdentifier == Schema.Version(10, 0, 0))
        #expect(LifeRPGMigrationPlan.schemas.count == 1)
        #expect(try ctx.fetchCount(FetchDescriptor<DailyQuest>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<LedgerEntry>()) == 0)
    }

    @Test func seedsBothTablesFromDoc() throws {
        let ctx = try makeContext()
        let expectedQuests = try SeedParser.sideQuests(csv: Fixtures.csv("side_quests.csv")).count
        let expectedRoutines = try SeedParser.routines(csv: Fixtures.csv("routine_quests.csv")).count

        let result = try merge(ctx)
        #expect(result == .init(questTemplates: expectedQuests, routineTasks: expectedRoutines))
        #expect(try ctx.fetchCount(FetchDescriptor<QuestTemplate>()) == expectedQuests)
        #expect(try ctx.fetchCount(FetchDescriptor<RoutineTask>()) == expectedRoutines)

        let office = try #require(try ctx.fetch(FetchDescriptor<RoutineTask>())
            .first { $0.text == "Go to the office" })
        #expect(!office.isActive)

        let weekend = try ctx.fetch(FetchDescriptor<QuestTemplate>(predicate: #Predicate { $0.weekendOnly }))
        #expect(!weekend.isEmpty)
        #expect(weekend.allSatisfy { $0.difficultyRaw == Difficulty.hard.rawValue })
    }

    @Test func secondRunInsertsNothing() throws {
        let ctx = try makeContext()
        let first = try merge(ctx)
        let again = try merge(ctx)
        #expect(again == .init(questTemplates: 0, routineTasks: 0))
        #expect(try ctx.fetchCount(FetchDescriptor<QuestTemplate>()) == first.questTemplates)
    }

    // MARK: the CSVs are an initial draft, read once

    /// The library in the store is the truth. A CSV that gains a row later does not reach a store
    /// that already has rows: the user adds to their own library from the Library page.
    @Test func aCSVThatGrowsLaterDoesNotReachAStoreThatHasRows() throws {
        let ctx = try makeContext()
        try merge(ctx)
        let before = try ctx.fetchCount(FetchDescriptor<QuestTemplate>())

        let extended = try Fixtures.csv("side_quests.csv") + "Learn to juggle,M,FALSE,FALSE,14,,,,\n"
        let result = try merge(ctx, side: extended)

        #expect(result == .init(questTemplates: 0, routineTasks: 0))
        #expect(try ctx.fetchCount(FetchDescriptor<QuestTemplate>()) == before)
    }

    /// The reason the rule changed: a row the user renamed or deleted used to come back, because
    /// the merge only knew a row by its words.
    @Test func aRenamedOrDeletedSeedRowDoesNotComeBack() throws {
        let ctx = try makeContext()
        try merge(ctx)
        let count = try ctx.fetchCount(FetchDescriptor<QuestTemplate>())
        let routineCount = try ctx.fetchCount(FetchDescriptor<RoutineTask>())

        let water = try #require(try ctx.fetch(FetchDescriptor<QuestTemplate>())
            .first { $0.text == "Drink 2L of water" })
        try LibraryEdit.rename("Drink two litres", .quest, id: water.id, in: ctx)
        let office = try #require(try ctx.fetch(FetchDescriptor<RoutineTask>())
            .first { $0.text == "Go to the office" })
        try LibraryEdit.archive(.routine, id: office.id, in: ctx)

        try merge(ctx)                                                       // the next launch
        #expect(try ctx.fetchCount(FetchDescriptor<QuestTemplate>()) == count)
        #expect(try ctx.fetchCount(FetchDescriptor<RoutineTask>()) == routineCount)
        #expect(try ctx.fetch(FetchDescriptor<QuestTemplate>()).filter { $0.text == "Drink 2L of water" }.isEmpty)
    }

    /// An edit made in the app must survive the next launch, and so must a store the user has
    /// turned inside out.
    @Test func existingRowsAreNotOverwritten() throws {
        let ctx = try makeContext()
        try merge(ctx)

        let water = try #require(try ctx.fetch(FetchDescriptor<QuestTemplate>())
            .first { $0.text == "Drink 2L of water" })
        water.isActive = false
        water.affinity = -2
        try ctx.save()

        // Same text, different difficulty — must be ignored, not applied and not inserted.
        let edited = try Fixtures.csv("side_quests.csv")
            .replacingOccurrences(of: "Drink 2L of water,E,low", with: "Drink 2L of water,H,high")
        let result = try merge(ctx, side: edited)

        #expect(result.questTemplates == 0)
        let after = try #require(try ctx.fetch(FetchDescriptor<QuestTemplate>())
            .first { $0.text == "Drink 2L of water" })
        #expect(after.difficulty == .easy)
        #expect(!after.isActive)
        #expect(after.affinity == -2)
    }

    /// "Empty" means no row in either library, archived ones included: a user who archived every
    /// row has not started over.
    @Test func aStoreWithOnlyOneKindOfRowOrOnlyArchivedRowsIsNotEmpty() throws {
        let onlyRoutine = try makeContext()
        let r = RoutineTask(); r.text = "Mine"; r.spec = "MON"
        onlyRoutine.insert(r)
        try onlyRoutine.save()
        #expect(try merge(onlyRoutine) == .init(questTemplates: 0, routineTasks: 0))

        let archivedOnly = try makeContext()
        let q = QuestTemplate(); q.text = "Mine"; q.isActive = false; q.isArchived = true
        archivedOnly.insert(q)
        try archivedOnly.save()
        #expect(try merge(archivedOnly) == .init(questTemplates: 0, routineTasks: 0))
    }

    @Test func duplicateTextsInCSVAreInsertedOnce() throws {
        let ctx = try makeContext()
        let csv = """
        text,difficulty,hidden_eligible,weekend_only
        Floss,T,FALSE,FALSE
        Floss,T,FALSE,FALSE
        """
        let result = try merge(ctx, side: csv)
        #expect(result.questTemplates == 1)
    }

    @Test func cooldownOverrideOnlyWhenDifferentFromDefault() throws {
        let ctx = try makeContext()
        try merge(ctx)
        let all = try ctx.fetch(FetchDescriptor<QuestTemplate>())
        let water = try #require(all.first { $0.text == "Drink 2L of water" })          // E, 3 = default
        #expect(water.cooldownDaysOverride == nil)
        let album = try #require(all.first { $0.text == "Listen to a new album start to finish" })  // E, 7
        #expect(album.cooldownDaysOverride == 7)
        let cookMeal = try #require(all.first { $0.text == "Cook yourself a meal" })     // M, 3
        #expect(cookMeal.cooldownDaysOverride == 3)
    }

    // MARK: downgrade versions

    /// `downgrade_of` is resolved to ids at import: the child row is inserted like any routine,
    /// and the parents it names gain it in `downgradeIDs`.
    @Test func downgradeVersionsAreLinkedToTheirParents() throws {
        let ctx = try Fixtures.context()
        try merge(ctx)
        let routines = try ctx.fetch(FetchDescriptor<RoutineTask>())
        let walk = try #require(routines.first { $0.text == "Walk, 30 minutes" })
        for parent in ["Workout: dumbbell training", "Workout: weight training"] {
            let r = try #require(routines.first { $0.text == parent })
            #expect(r.downgradeIDs == [walk.id])
            #expect(Degrade.versions(of: r, in: routines).map(\.text) == ["Walk, 30 minutes"])
        }
        // A strength routine's only lighter version is a walk — never lighter weights, which is
        // what makes the first cycle days mean "no strength training".
        #expect(walk.autoVerify == .calendarWorkout(minutes: 30))
    }

    /// The old repair (linking versions onto rows an older store already had) is gone with the
    /// merge: a store that has rows is not read from the CSV at all. Whatever links it has stay.
    @Test func aStoreThatHasRowsIsNotRelinked() throws {
        let ctx = try Fixtures.context()
        let existing = RoutineTask()
        existing.text = "Workout: weight training"
        existing.spec = "SAT,SUN"
        ctx.insert(existing)
        try ctx.save()

        let result = try merge(ctx)
        #expect(result.routineTasks == 0 && existing.downgradeIDs.isEmpty)
        #expect(try ctx.fetchCount(FetchDescriptor<RoutineTask>()) == 1)
    }
}
