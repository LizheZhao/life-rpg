import Foundation
import SwiftData
@testable import LifeRPGCore

/// What an app before schema 9 wrote for the library: the ids and texts the history points at
/// (`library`), the user's own rows in full (`userLibrary`), and what the user changed on the seed
/// rows (`libraryChanges`). Production no longer writes any of it, but import still has to read it
/// from the backups already on the user's phone, so the tests make such files here.
enum LegacyBackup {
    static let noQuestsCSV = "text,difficulty,hidden_eligible,weekend_only,cooldown_days,auto_verify,launch_url,variants,is_active\n"
    static let noRoutinesCSV = "text,frequency_kind,frequency_spec,weekly_target,base_points,difficulty,flexible_within_week,counts_for_clear,is_active,downgrade_of,auto_verify,launch_url,notes\n"

    /// A schema 8 file that records no seed changes (no CSV to compare against), the way an old
    /// build did when it had none to hand.
    static func data(_ context: ModelContext) throws -> Data {
        try data(context, sideQuestsCSV: noQuestsCSV, routinesCSV: noRoutinesCSV)
    }

    /// A schema 8 file for `context`: the current history, and the library the old way.
    static func data(_ context: ModelContext, sideQuestsCSV: String, routinesCSV: String) throws -> Data {
        var s = try JSONExport.snapshot(context)
        let templates = try context.fetch(FetchDescriptor<QuestTemplate>())
        let routines = try context.fetch(FetchDescriptor<RoutineTask>())
        let referenced = referencedLibraryIDs(
            quests: try context.fetch(FetchDescriptor<DailyQuest>()),
            occurrences: try context.fetch(FetchDescriptor<RoutineOccurrence>()),
            ratings: try context.fetch(FetchDescriptor<QuestRating>()),
            comments: try context.fetch(FetchDescriptor<QuestComment>()))

        s.schemaVersion = 8
        s.fullLibrary = nil
        s.library = JSONExport.Library(
            quests: templates
                .filter { referenced.contains($0.id) || $0.lastServedDayKey != nil || $0.lastCompletedDayKey != nil }
                .sorted { $0.text < $1.text }
                .map { JSONExport.LibraryQuest(id: $0.id, text: $0.text, lastServedDayKey: $0.lastServedDayKey,
                                               lastCompletedDayKey: $0.lastCompletedDayKey) },
            routines: routines
                .filter { referenced.contains($0.id) || $0.lastCompletedDayKey != nil }
                .sorted { $0.text < $1.text }
                .map { JSONExport.LibraryRoutine(id: $0.id, text: $0.text, lastCompletedDayKey: $0.lastCompletedDayKey) })

        let mine = JSONExport.UserLibrary(
            quests: templates.filter { $0.origin == .user }.sorted { $0.text < $1.text }.map {
                JSONExport.UserQuest(id: $0.id, text: $0.text, difficulty: $0.difficultyRaw,
                                     hiddenEligible: $0.hiddenEligible, weekendOnly: $0.weekendOnly,
                                     cooldownDaysOverride: $0.cooldownDaysOverride, variants: $0.variants,
                                     launchURL: $0.launchURLString, autoVerifyRule: $0.autoVerifyRule,
                                     isActive: $0.isActive)
            },
            routines: routines.filter { $0.origin == .user }.sorted { $0.text < $1.text }.map {
                JSONExport.UserRoutine(id: $0.id, text: $0.text, difficulty: $0.difficultyRaw, basePoints: $0.basePoints,
                                       kind: $0.kindRaw, spec: $0.spec, anchorWeekKey: $0.anchorWeekKey,
                                       weeklyTarget: $0.weeklyTarget, flexibleWithinWeek: $0.flexibleWithinWeek,
                                       countsForClear: $0.countsForClear, downgradeIDs: $0.downgradeIDs,
                                       launchURL: $0.launchURLString, autoVerifyRule: $0.autoVerifyRule,
                                       isActive: $0.isActive)
            })
        s.userLibrary = mine.quests.isEmpty && mine.routines.isEmpty ? nil : mine

        let quests = Dictionary(try SeedParser.sideQuests(csv: sideQuestsCSV).map { ($0.text, $0) },
                                uniquingKeysWith: { a, _ in a })
        let seeds = Dictionary(try SeedParser.routines(csv: routinesCSV).map { ($0.text, $0) },
                               uniquingKeysWith: { a, _ in a })
        let changedQuests = templates.filter { $0.origin == .seed }.compactMap { t -> JSONExport.QuestChange? in
            guard let seed = quests[t.text], seed.isActive != t.isActive else { return nil }
            return .init(text: t.text, isActive: t.isActive)
        }
        let changedRoutines = routines.filter { $0.origin == .seed }.compactMap { r -> JSONExport.RoutineChange? in
            guard let seed = seeds[r.text], seed.isActive != r.isActive || seed.basePoints != r.basePoints else { return nil }
            return .init(text: r.text, isActive: r.isActive, basePoints: r.basePoints)
        }
        s.libraryChanges = changedQuests.isEmpty && changedRoutines.isEmpty
            ? nil : JSONExport.LibraryChanges(quests: changedQuests, routines: changedRoutines)
        return try JSONExport.encode(s)
    }

    /// The ids of every library row the history tables point at: what the old `library` block had
    /// to be able to re-point.
    static func referencedLibraryIDs(quests: [DailyQuest], occurrences: [RoutineOccurrence],
                                     ratings: [QuestRating], comments: [QuestComment]) -> Set<UUID> {
        var ids = Set<UUID>()
        for q in quests {
            if let id = q.templateID { ids.insert(id) }
            ids.formUnion(q.trivialTemplateIDs)
        }
        for o in occurrences {
            for id in [o.routineID, o.adHocSourceRoutineID, o.degradedRoutineID] { if let id { ids.insert(id) } }
        }
        for id in ratings.compactMap(\.targetID) + comments.compactMap(\.targetID) { ids.insert(id) }
        return ids
    }
}
