import Foundation
import SwiftData

public enum SeedImporter {
    public struct Result: Equatable, Sendable {
        public var questTemplates: Int
        public var routineTasks: Int
    }

    /// Starts an empty library from these rows, once. They come from the starter library
    /// (`StarterLibrary`), which is an initial draft: the library in the store is the truth from
    /// then on, edited, extended and pruned in the app, so a store that already has any row (either
    /// table, archived ones included) is left exactly as it is. That is also why a row the user
    /// renamed or deleted can no longer come back: nothing reads the starter file again to look for
    /// it. Returns how many rows were inserted.
    ///
    /// Duplicate texts are inserted once, and each `downgradeOf` is resolved to the ids of the rows
    /// just inserted.
    @discardableResult
    public static func seedIfEmpty(_ context: ModelContext,
                                   quests: [SideQuestSeed],
                                   routines routineSeeds: [RoutineSeed]) throws -> Result {
        var result = Result(questTemplates: 0, routineTasks: 0)
        guard try context.fetchCount(FetchDescriptor<QuestTemplate>()) == 0,
              try context.fetchCount(FetchDescriptor<RoutineTask>()) == 0 else { return result }

        var knownQuests = Set<String>()
        for seed in quests where knownQuests.insert(seed.text).inserted {
            context.insert(QuestTemplate(seed: seed))
            result.questTemplates += 1
        }

        var routinesByText: [String: RoutineTask] = [:]
        for seed in routineSeeds where routinesByText[seed.text] == nil {
            let routine = RoutineTask(seed: seed)
            context.insert(routine)
            routinesByText[seed.text] = routine
            result.routineTasks += 1
        }

        for seed in routineSeeds where !seed.downgradeOf.isEmpty {
            guard let version = routinesByText[seed.text] else { continue }
            for parentText in seed.downgradeOf {
                guard let parent = routinesByText[parentText],
                      !parent.downgradeIDs.contains(version.id) else { continue }
                parent.downgradeIDs.append(version.id)
            }
        }

        try context.save()
        return result
    }
}

extension QuestTemplate {
    convenience init(seed: SideQuestSeed) {
        self.init()
        text = seed.text
        difficulty = seed.difficulty
        hiddenEligible = seed.hiddenEligible
        weekendOnly = seed.weekendOnly
        // Only store an override when it differs from the difficulty default.
        if let days = seed.cooldownDays, days != seed.difficulty.cooldownDays {
            cooldownDaysOverride = days
        }
        variants = seed.variants
        launchURLString = seed.launchURLString
        autoVerifyRule = seed.autoVerifyRule
        isActive = seed.isActive
        starterKey = seed.starterKey
    }
}

extension RoutineTask {
    convenience init(seed: RoutineSeed) {
        self.init()
        text = seed.text
        basePoints = seed.basePoints
        difficulty = seed.difficulty
        kind = seed.kind
        spec = seed.spec
        weeklyTarget = seed.weeklyTarget
        flexibleWithinWeek = seed.flexibleWithinWeek
        countsForClear = seed.countsForClear
        launchURLString = seed.launchURLString
        autoVerifyRule = seed.autoVerifyRule
        isActive = seed.isActive
        starterKey = seed.starterKey
    }
}
