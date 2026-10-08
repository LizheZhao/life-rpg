import Foundation
import SwiftData

/// What a later version of the starter library offers an install that already has a library.
///
/// A row is a starter row when it carries the file's key for it (`starterKey`, stamped at install
/// and when added from here), so a row the user renamed or deleted (archived) still counts as
/// present and is never offered again. Rows from before keys existed carry none; `claim` matches
/// those by their words, once, and keys them. Nothing is added by itself: the user picks, and only
/// additions are made. Existing rows are never changed, apart from a lighter version being linked
/// to the routine it belongs to.
public enum StarterUpdate {
    public struct Item: Equatable, Identifiable, Sendable {
        public enum Kind: String, Sendable { case quest, routine }
        public var kind: Kind
        public var key: String
        public var text: String
        public var difficulty: Difficulty
        /// A routine that is only ever reached through another (`downgradeOf`).
        public var isLightVersion: Bool

        /// Unique across quests and routines; also what the app stores for a dismissed row.
        public var id: String { "\(kind.rawValue):\(key)" }
    }

    /// Stamps the key on every row that has none and says the same words as a starter row (case and
    /// surrounding spaces ignored, archived rows included). A key another row already holds is never
    /// taken twice.
    public static func claim(_ library: StarterLibrary, in context: ModelContext) throws {
        let templates = try context.fetch(FetchDescriptor<QuestTemplate>())
        var held = Set(templates.compactMap(\.starterKey))
        for seed in library.quests {
            guard let key = seed.starterKey, !held.contains(key),
                  let row = templates.first(where: { $0.starterKey == nil && same($0.text, seed.text) }) else { continue }
            row.starterKey = key; held.insert(key)
        }
        let routines = try context.fetch(FetchDescriptor<RoutineTask>())
        var heldRoutines = Set(routines.compactMap(\.starterKey))
        for seed in library.routines {
            guard let key = seed.starterKey, !heldRoutines.contains(key),
                  let row = routines.first(where: { $0.starterKey == nil && same($0.text, seed.text) }) else { continue }
            row.starterKey = key; heldRoutines.insert(key)
        }
        try context.save()
    }

    /// The starter rows this library does not have yet, quests then routines, in the file's order,
    /// minus `dismissed` ids. A lighter version is offered only when a routine it belongs to is in
    /// the library or offered too.
    public static func offered(_ library: StarterLibrary, in context: ModelContext,
                               dismissed: Set<String> = []) throws -> [Item] {
        let state = try State(context)
        var items: [Item] = library.quests.compactMap { seed in
            guard let key = seed.starterKey, !state.questKeys.contains(key) else { return nil }
            return Item(kind: .quest, key: key, text: seed.text, difficulty: seed.difficulty, isLightVersion: false)
        }
        let missing = library.routines.filter { seed in
            guard let key = seed.starterKey else { return false }
            return !state.routineKeys.contains(key)
        }
        let candidates = missing.map { seed in
            Item(kind: .routine, key: seed.starterKey!, text: seed.text, difficulty: seed.difficulty,
                 isLightVersion: !seed.downgradeOf.isEmpty)
        }
        let parents = candidates.filter { !$0.isLightVersion && !dismissed.contains($0.id) }
        let reachable = Set(state.routineTexts).union(parents.map { normal($0.text) })
        for (seed, item) in zip(missing, candidates) {
            if item.isLightVersion, !seed.downgradeOf.contains(where: { reachable.contains(normal($0)) }) { continue }
            items.append(item)
        }
        return items.filter { !dismissed.contains($0.id) }
    }

    /// Adds the starter rows whose `Item.id` is in `ids` (unknown ids and rows already present are
    /// ignored), stamps their keys and links lighter versions to the routines they belong to.
    @discardableResult
    public static func add(_ ids: Set<String>, from library: StarterLibrary,
                           in context: ModelContext) throws -> SeedImporter.Result {
        var result = SeedImporter.Result(questTemplates: 0, routineTasks: 0)
        let state = try State(context)

        for seed in library.quests {
            guard let key = seed.starterKey, ids.contains("quest:\(key)"), !state.questKeys.contains(key) else { continue }
            context.insert(QuestTemplate(seed: seed))
            result.questTemplates += 1
        }

        var added: [String: RoutineTask] = [:]      // normalized text → new row
        for seed in library.routines {
            guard let key = seed.starterKey, ids.contains("routine:\(key)"), !state.routineKeys.contains(key) else { continue }
            let row = RoutineTask(seed: seed)
            context.insert(row)
            added[normal(seed.text)] = row
            result.routineTasks += 1
        }

        // Lighter versions: link a light version and a parent whenever either of them is new.
        let all = try context.fetch(FetchDescriptor<RoutineTask>())
        func row(key: String?, text: String) -> RoutineTask? {
            all.first { $0.starterKey == key && key != nil } ?? all.first { $0.starterKey == nil && same($0.text, text) }
        }
        for seed in library.routines where !seed.downgradeOf.isEmpty {
            guard let light = row(key: seed.starterKey, text: seed.text) else { continue }
            for parentText in seed.downgradeOf {
                let parentSeed = library.routines.first { same($0.text, parentText) }
                guard let parent = row(key: parentSeed?.starterKey, text: parentText), parent.id != light.id,
                      added[normal(seed.text)] != nil || added[normal(parentText)] != nil,
                      !parent.downgradeIDs.contains(light.id) else { continue }
                parent.downgradeIDs.append(light.id)
            }
        }
        try context.save()
        return result
    }

    // MARK: helpers

    private struct State {
        var questKeys: Set<String>
        var routineKeys: Set<String>
        var routineTexts: [String]

        init(_ context: ModelContext) throws {
            questKeys = Set(try context.fetch(FetchDescriptor<QuestTemplate>()).compactMap(\.starterKey))
            let routines = try context.fetch(FetchDescriptor<RoutineTask>())
            routineKeys = Set(routines.compactMap(\.starterKey))
            routineTexts = routines.map { normal($0.text) }
        }
    }

    private static func normal(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private static func same(_ a: String, _ b: String) -> Bool { normal(a) == normal(b) }
}
