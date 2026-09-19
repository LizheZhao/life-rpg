import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

struct SeedImporterTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(LifeRPGSchema.models), configurations: config)
        return ModelContext(container)
    }

    @Test func seedsBothTablesFromDoc() throws {
        let ctx = try makeContext()
        let result = try SeedImporter.seedIfEmpty(ctx,
                                                  sideQuestsCSV: Fixtures.csv("side_quests.csv"),
                                                  routinesCSV: Fixtures.csv("routine_quests.csv"))
        #expect(result == .init(questTemplates: 75, routineTasks: 13))
        #expect(try ctx.fetchCount(FetchDescriptor<QuestTemplate>()) == 75)
        #expect(try ctx.fetchCount(FetchDescriptor<RoutineTask>()) == 13)

        let active = try ctx.fetchCount(FetchDescriptor<RoutineTask>(predicate: #Predicate { $0.isActive }))
        #expect(active == 12)

        let weekend = try ctx.fetch(FetchDescriptor<QuestTemplate>(predicate: #Predicate { $0.weekendOnly }))
        #expect(weekend.allSatisfy { $0.difficultyRaw == Difficulty.hard.rawValue })
    }

    @Test func secondRunIsNoOp() throws {
        let ctx = try makeContext()
        let side = try Fixtures.csv("side_quests.csv")
        let routines = try Fixtures.csv("routine_quests.csv")
        try SeedImporter.seedIfEmpty(ctx, sideQuestsCSV: side, routinesCSV: routines)
        let again = try SeedImporter.seedIfEmpty(ctx, sideQuestsCSV: side, routinesCSV: routines)
        #expect(again == .init(questTemplates: 0, routineTasks: 0))
        #expect(try ctx.fetchCount(FetchDescriptor<QuestTemplate>()) == 75)
    }

    @Test func cooldownOverrideOnlyWhenDifferentFromDefault() throws {
        let ctx = try makeContext()
        try SeedImporter.seedIfEmpty(ctx,
                                     sideQuestsCSV: Fixtures.csv("side_quests.csv"),
                                     routinesCSV: Fixtures.csv("routine_quests.csv"))
        let all = try ctx.fetch(FetchDescriptor<QuestTemplate>())
        let water = try #require(all.first { $0.text == "Drink 2L of water" })          // E, 3 = default
        #expect(water.cooldownDaysOverride == nil)
        let album = try #require(all.first { $0.text == "Listen to a new album start to finish" })  // E, 7
        #expect(album.cooldownDaysOverride == 7)
        let cookMeal = try #require(all.first { $0.text == "Cook yourself a meal" })     // M, 3
        #expect(cookMeal.cooldownDaysOverride == 3)
    }
}
