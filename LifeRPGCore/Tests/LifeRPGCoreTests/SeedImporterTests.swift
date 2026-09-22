import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

struct SeedImporterTests {
    private func makeContext() throws -> ModelContext {
        try Fixtures.context()
    }

    private func merge(_ ctx: ModelContext,
                       side: String? = nil,
                       routines: String? = nil) throws -> SeedImporter.Result {
        try SeedImporter.mergeSeeds(ctx,
                                    sideQuestsCSV: side ?? Fixtures.csv("side_quests.csv"),
                                    routinesCSV: routines ?? Fixtures.csv("routine_quests.csv"))
    }

    /// Guards the schema declaration: a model missing from `SchemaV1.models` fails here.
    @Test func containerOpensWithVersionedSchema() throws {
        let ctx = try makeContext()
        #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
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

    @Test func mergeInsertsOnlyNewRows() throws {
        let ctx = try makeContext()
        try merge(ctx)
        let before = try ctx.fetchCount(FetchDescriptor<QuestTemplate>())

        let extended = try Fixtures.csv("side_quests.csv") + "Learn to juggle,M,low,FALSE,FALSE,14,,,,\n"
        let result = try merge(ctx, side: extended)

        #expect(result == .init(questTemplates: 1, routineTasks: 0))
        #expect(try ctx.fetchCount(FetchDescriptor<QuestTemplate>()) == before + 1)
    }

    /// An edit made in the app must survive the next launch; the CSV never writes over a known text.
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

    @Test func duplicateTextsInCSVAreInsertedOnce() throws {
        let ctx = try makeContext()
        let csv = """
        text,difficulty,intensity,hidden_eligible,weekend_only
        Floss,T,low,FALSE,FALSE
        Floss,T,low,FALSE,FALSE
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
}
