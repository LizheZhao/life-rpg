import Foundation
import SwiftData

/// A dump of the history tables, read back by `JSONImport`.
///
/// Pulled forward from Stage 6 on purpose: until CloudKit is on, the only copy of real usage data
/// is this app's sandbox on one phone, and accumulating months of history with no way to get it
/// off the device is how it gets lost.
///
/// Templates and routines are not included: they are rebuilt from the seed CSVs, which live in
/// `doc/` under version control. What cannot be rebuilt is what happened, so that is what ships —
/// and that includes the ratings and comments you write in the app, which exist nowhere else, and
/// the rewards you typed in. `library` carries only what a reseed can't give back: the old id of
/// each row history points at, so history can be re-pointed at the new rows by text, and the
/// cooldown / schedule stamps. A row nothing refers to and nothing stamped is left out: with a
/// backup a day, the list is copied into every file, so it is kept to what is needed.
public enum JSONExport {
    /// Bumped when the model changes shape, independently of the GitHub tag. Import reads this
    /// and nothing else. 4 added `Occurrence.iconKey`, 5 the user's own library rows
    /// (`userLibrary`), 6 the journal, 7 `Turn.writingSeconds`, 8 the day documents
    /// (`journalEntries`); an older file simply lacks them.
    public static let schemaVersion = 8

    /// The oldest export import still reads. Anything between this and `schemaVersion` decodes into
    /// the current shape, the fields added since being optional.
    public static let oldestReadableVersion = 3

    public struct Snapshot: Codable, Equatable, Sendable {
        public var schemaVersion: Int
        public var exportedAt: Date
        public var ledger: [Ledger]
        public var dailyQuests: [Quest]
        public var routineOccurrences: [Occurrence]
        public var dailyContexts: [Context]
        public var ratings: [Rating]
        public var comments: [Comment]
        /// Nil in exports written before import existed; `JSONImport` refuses those.
        public var library: Library?
        public var rewards: [RewardRow]?
        /// The rows the user saved themselves (`LibraryOrigin.user`), in full: nothing else can give
        /// them back. Nil when there are none, which is most backups.
        public var userLibrary: UserLibrary?
        /// What the user changed on the seed rows (turned off or on, a routine's points): only the
        /// rows that differ from the CSV. Nil when nothing does, or when the CSVs weren't to hand.
        public var libraryChanges: LibraryChanges?
        /// Nil only in a file written before the journal existed (schema 5 and older). From 6 on the
        /// block is always written, empty or not, so import can tell "no journal in this backup" from
        /// "a backup with nothing in its journal" and leave the first alone.
        public var journal: Journal?
        /// The day documents. Nil only in a file written before schema 8; from 8 on the array is
        /// always written, empty or not, so import can tell "no entries in this backup" (an older
        /// file, whose entries are rebuilt from its turns) from "a backup with none".
        public var journalEntries: [JournalEntryRow]?
    }

    /// The seed CSVs' text, to tell what the user changed from what they started with.
    public struct Seeds: Sendable {
        public var sideQuestsCSV: String
        public var routinesCSV: String

        public init(sideQuestsCSV: String, routinesCSV: String) {
            self.sideQuestsCSV = sideQuestsCSV
            self.routinesCSV = routinesCSV
        }
    }

    public struct LibraryChanges: Codable, Equatable, Sendable {
        public var quests: [QuestChange]
        public var routines: [RoutineChange]
    }

    public struct QuestChange: Codable, Equatable, Sendable {
        public var text: String
        public var isActive: Bool
    }

    public struct RoutineChange: Codable, Equatable, Sendable {
        public var text: String
        public var isActive: Bool
        public var basePoints: Int
    }

    public struct UserLibrary: Codable, Equatable, Sendable {
        public var quests: [UserQuest]
        public var routines: [UserRoutine]
    }

    public struct UserQuest: Codable, Equatable, Sendable {
        public var id: UUID
        public var text: String
        public var difficulty: String
        public var hiddenEligible: Bool
        public var weekendOnly: Bool
        public var cooldownDaysOverride: Int?
        public var variants: [String]
        public var launchURL: String?
        public var autoVerifyRule: String?
        public var isActive: Bool
    }

    public struct UserRoutine: Codable, Equatable, Sendable {
        public var id: UUID
        public var text: String
        public var difficulty: String
        public var basePoints: Int
        public var kind: String
        public var spec: String
        public var anchorWeekKey: String?
        public var weeklyTarget: Int
        public var flexibleWithinWeek: Bool
        public var countsForClear: Bool
        public var downgradeIDs: [UUID]
        public var launchURL: String?
        public var autoVerifyRule: String?
        public var isActive: Bool
    }

    /// Not the library itself — the seed CSVs are — but the per-row state the history leans on.
    public struct Library: Codable, Equatable, Sendable {
        public var quests: [LibraryQuest]
        public var routines: [LibraryRoutine]
    }

    public struct LibraryQuest: Codable, Equatable, Sendable {
        public var id: UUID
        public var text: String
        public var lastServedDayKey: String?
        public var lastCompletedDayKey: String?
    }

    public struct LibraryRoutine: Codable, Equatable, Sendable {
        public var id: UUID
        public var text: String
        public var lastCompletedDayKey: String?
    }

    public struct RewardRow: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var estimatedCost: Double
        public var virtualKind: String?
        public var fixedCoins: Int?
        public var isActive: Bool
        /// The pinned savings goal. Optional so an export written before it existed still reads
        /// (as not a goal).
        public var isGoal: Bool?
    }

    public struct Ledger: Codable, Equatable, Sendable {
        public var id: UUID
        public var timestamp: Date
        public var dayKey: String
        public var kind: String
        public var points: Int
        public var refID: UUID?
        public var note: String
    }

    public struct Quest: Codable, Equatable, Sendable {
        public var id: UUID
        public var dayKey: String
        public var weekKey: String
        public var slot: String
        public var isHiddenSlot: Bool
        public var templateID: UUID?
        public var text: String
        public var trivialGroup: [String]
        public var trivialDone: [Bool]
        public var trivialTemplateIDs: [UUID]
        public var trivialVariants: [String]
        public var variant: String?
        public var launchURL: String?
        public var points: Int?
        public var completedAt: Date?
        public var sourceType: String
        public var rerollCount: Int
        public var replaced: Bool
        public var replacedReason: String?
        public var extensionCount: Int
    }

    public struct Occurrence: Codable, Equatable, Sendable {
        public var id: UUID
        public var routineID: UUID?
        public var dueDayKey: String
        public var weekKey: String
        public var completedDayKey: String?
        public var text: String
        public var usedDegraded: Bool
        public var basePoints: Int
        public var countsForClear: Bool
        public var awardedPoints: Int?
        public var penaltyApplied: Int
        public var skipped: Bool
        public var completedAt: Date?
        public var replacesQuestID: UUID?
        public var adHocSourceRoutineID: UUID?
        public var replacedByID: UUID?
        public var degradedText: String?
        public var degradedRoutineID: UUID?
        public var degradedBasePoints: Int?
        public var sourceType: String
        /// The doodle chosen for a custom ad-hoc routine; absent in a v3 export.
        public var iconKey: String?
    }

    public struct Context: Codable, Equatable, Sendable {
        public var dayKey: String
        public var hrv: Double?
        public var sleepHours: Double?
        public var restingHR: Double?
        public var energy: Double
        public var readiness: Int
        public var tier: String
        public var onCycle: Bool
        public var cycleDay: Int?
        public var routineLoad: Int
        public var randomSlots: Int
    }

    public struct Rating: Codable, Equatable, Sendable {
        public var id: UUID
        public var targetID: UUID?
        /// The `DailyQuest` (or occurrence) this was rated right after. Without it a restored
        /// rating can only say "this quest, in September", not which completion prompted it —
        /// and that join is the whole reason the field exists.
        public var questID: UUID?
        public var targetKind: String
        public var text: String
        public var rating: Int
        public var dayKey: String
        public var timestamp: Date
    }

    public struct Comment: Codable, Equatable, Sendable {
        public var id: UUID
        public var targetID: UUID?
        public var questID: UUID?
        public var targetKind: String
        public var text: String
        public var comment: String
        public var dayKey: String
        public var timestamp: Date
    }

    public struct Journal: Codable, Equatable, Sendable {
        public var turns: [Turn]
    }

    /// One day's document. `blocks` are the objects documented on `JournalBlock`. The row's own id
    /// is not carried: nothing points at an entry.
    public struct JournalEntryRow: Codable, Equatable, Sendable {
        public var dayKey: String
        public var blocks: [JournalBlock]
        public var createdAt: Date
        public var updatedAt: Date
        /// Nil is a draft.
        public var doneAt: Date?
    }

    /// `subjectID` is a `DailyQuest` or `RoutineOccurrence` id, both kept through import, so it is
    /// carried as it is, the same way a rating's `questID` is.
    public struct Turn: Codable, Equatable, Sendable {
        public var id: UUID
        public var dayKey: String
        public var index: Int
        public var kind: String
        public var promptID: String
        public var question: String
        public var subjectKind: String?
        public var subjectID: UUID?
        public var subjectText: String
        public var answer: String
        public var outcome: String
        public var source: String
        public var language: String
        public var askedAt: Date
        public var answeredAt: Date
        /// Nil in a file written before schema 7, which restores as 0.
        public var writingSeconds: Int?
    }

    /// The ids of every library row the history tables point at — what `library` has to be able to
    /// re-point on import.
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

    /// The seed rows whose on / off or points differ from the CSVs they came from. A row the
    /// user never touched is exactly what a reseed brings back, so it is not listed.
    static func libraryChanges(templates: [QuestTemplate], routines: [RoutineTask],
                               seeds: Seeds) -> LibraryChanges? {
        guard let quests = try? SeedParser.sideQuests(csv: seeds.sideQuestsCSV),
              let routineSeeds = try? SeedParser.routines(csv: seeds.routinesCSV) else { return nil }
        let questByText = Dictionary(quests.map { ($0.text, $0) }, uniquingKeysWith: { a, _ in a })
        let routineByText = Dictionary(routineSeeds.map { ($0.text, $0) }, uniquingKeysWith: { a, _ in a })
        let changedQuests = templates.filter { $0.origin == .seed }
            .compactMap { t -> QuestChange? in
                guard let seed = questByText[t.text], seed.isActive != t.isActive else { return nil }
                return QuestChange(text: t.text, isActive: t.isActive)
            }.sorted { $0.text < $1.text }
        let changedRoutines = routines.filter { $0.origin == .seed }
            .compactMap { r -> RoutineChange? in
                guard let seed = routineByText[r.text],
                      seed.isActive != r.isActive || seed.basePoints != r.basePoints else { return nil }
                return RoutineChange(text: r.text, isActive: r.isActive, basePoints: r.basePoints)
            }.sorted { $0.text < $1.text }
        return changedQuests.isEmpty && changedRoutines.isEmpty
            ? nil : LibraryChanges(quests: changedQuests, routines: changedRoutines)
    }

    public static func snapshot(_ context: ModelContext, seeds: Seeds? = nil, now: Date = Date()) throws -> Snapshot {
        let quests = try context.fetch(FetchDescriptor<DailyQuest>())
        let occurrences = try context.fetch(FetchDescriptor<RoutineOccurrence>())
        let ratings = try context.fetch(FetchDescriptor<QuestRating>())
        let comments = try context.fetch(FetchDescriptor<QuestComment>())
        let referenced = referencedLibraryIDs(quests: quests, occurrences: occurrences,
                                              ratings: ratings, comments: comments)
        let templates = try context.fetch(FetchDescriptor<QuestTemplate>())
        let routines = try context.fetch(FetchDescriptor<RoutineTask>())
        let mine = UserLibrary(
            quests: templates.filter { $0.origin == .user }.sorted { $0.text < $1.text }.map {
                UserQuest(id: $0.id, text: $0.text, difficulty: $0.difficultyRaw,
                          hiddenEligible: $0.hiddenEligible, weekendOnly: $0.weekendOnly,
                          cooldownDaysOverride: $0.cooldownDaysOverride, variants: $0.variants,
                          launchURL: $0.launchURLString, autoVerifyRule: $0.autoVerifyRule, isActive: $0.isActive)
            },
            routines: routines.filter { $0.origin == .user }.sorted { $0.text < $1.text }.map {
                UserRoutine(id: $0.id, text: $0.text, difficulty: $0.difficultyRaw, basePoints: $0.basePoints,
                            kind: $0.kindRaw, spec: $0.spec, anchorWeekKey: $0.anchorWeekKey,
                            weeklyTarget: $0.weeklyTarget, flexibleWithinWeek: $0.flexibleWithinWeek,
                            countsForClear: $0.countsForClear, downgradeIDs: $0.downgradeIDs,
                            launchURL: $0.launchURLString, autoVerifyRule: $0.autoVerifyRule, isActive: $0.isActive)
            })
        return Snapshot(
            schemaVersion: schemaVersion,
            exportedAt: now,
            ledger: try context.fetch(FetchDescriptor<LedgerEntry>()).sorted { $0.timestamp < $1.timestamp }.map {
                Ledger(id: $0.id, timestamp: $0.timestamp, dayKey: $0.dayKey, kind: $0.kind,
                       points: $0.points, refID: $0.refID, note: $0.note)
            },
            dailyQuests: quests.sorted { $0.dayKey < $1.dayKey }.map {
                Quest(id: $0.id, dayKey: $0.dayKey, weekKey: $0.weekKey, slot: $0.slotRaw,
                      isHiddenSlot: $0.isHiddenSlot, templateID: $0.templateID, text: $0.textSnapshot,
                      trivialGroup: $0.trivialGroup, trivialDone: $0.trivialDone,
                      trivialTemplateIDs: $0.trivialTemplateIDs,
                      trivialVariants: $0.trivialVariants, variant: $0.variantSnapshot,
                      launchURL: $0.launchURLSnapshot, points: $0.points,
                      completedAt: $0.completedAt, sourceType: $0.sourceTypeRaw,
                      rerollCount: $0.rerollCount, replaced: $0.replaced,
                      replacedReason: $0.replacedReasonRaw, extensionCount: $0.extensionCount)
            },
            routineOccurrences: occurrences.sorted { $0.dueDayKey < $1.dueDayKey }.map {
                Occurrence(id: $0.id, routineID: $0.routineID, dueDayKey: $0.dueDayKey, weekKey: $0.weekKey,
                           completedDayKey: $0.completedDayKey, text: $0.textSnapshot,
                           usedDegraded: $0.usedDegraded, basePoints: $0.basePoints,
                           countsForClear: $0.countsForClear,
                           awardedPoints: $0.awardedPoints, penaltyApplied: $0.penaltyApplied,
                           skipped: $0.skipped, completedAt: $0.completedAt,
                           replacesQuestID: $0.replacesQuestID, adHocSourceRoutineID: $0.adHocSourceRoutineID,
                           replacedByID: $0.replacedByID,
                           degradedText: $0.degradedTextSnapshot,
                           degradedRoutineID: $0.degradedRoutineID,
                           degradedBasePoints: $0.degradedBasePoints, sourceType: $0.sourceTypeRaw,
                           iconKey: $0.iconKey)
            },
            dailyContexts: try context.fetch(FetchDescriptor<DailyContext>()).sorted { $0.dayKey < $1.dayKey }.map {
                Context(dayKey: $0.dayKey, hrv: $0.hrv, sleepHours: $0.sleepHours, restingHR: $0.restingHR,
                        energy: $0.energy, readiness: $0.readiness, tier: $0.tierRaw, onCycle: $0.onCycle,
                        cycleDay: $0.cycleDay, routineLoad: $0.routineLoad, randomSlots: $0.randomSlots)
            },
            ratings: ratings.sorted { $0.timestamp < $1.timestamp }.map {
                Rating(id: $0.id, targetID: $0.targetID, questID: $0.questID,
                       targetKind: $0.targetKindRaw,
                       text: $0.textSnapshot, rating: $0.rating, dayKey: $0.dayKey,
                       timestamp: $0.timestamp)
            },
            comments: comments.sorted { $0.timestamp < $1.timestamp }.map {
                Comment(id: $0.id, targetID: $0.targetID, questID: $0.questID,
                        targetKind: $0.targetKindRaw,
                        text: $0.textSnapshot, comment: $0.comment, dayKey: $0.dayKey,
                        timestamp: $0.timestamp)
            },
            library: Library(
                quests: templates
                    .filter { referenced.contains($0.id) || $0.lastServedDayKey != nil || $0.lastCompletedDayKey != nil }
                    .sorted { $0.text < $1.text }.map {
                        LibraryQuest(id: $0.id, text: $0.text, lastServedDayKey: $0.lastServedDayKey,
                                     lastCompletedDayKey: $0.lastCompletedDayKey)
                    },
                routines: routines
                    .filter { referenced.contains($0.id) || $0.lastCompletedDayKey != nil }
                    .sorted { $0.text < $1.text }.map {
                        LibraryRoutine(id: $0.id, text: $0.text, lastCompletedDayKey: $0.lastCompletedDayKey)
                    }),
            rewards: try context.fetch(FetchDescriptor<Reward>()).sorted { $0.name < $1.name }.map {
                RewardRow(id: $0.id, name: $0.name, estimatedCost: $0.estimatedCost,
                          virtualKind: $0.virtualKind, fixedCoins: $0.fixedCoins, isActive: $0.isActive,
                          isGoal: $0.isGoal)
            },
            userLibrary: mine.quests.isEmpty && mine.routines.isEmpty ? nil : mine,
            libraryChanges: seeds.flatMap { libraryChanges(templates: templates, routines: routines, seeds: $0) },
            journal: Journal(turns: try context.fetch(FetchDescriptor<JournalTurn>())
                .sorted { ($0.dayKey, $0.index) < ($1.dayKey, $1.index) }.map {
                    Turn(id: $0.id, dayKey: $0.dayKey, index: $0.index, kind: $0.kindRaw,
                         promptID: $0.promptID, question: $0.questionText, subjectKind: $0.subjectKindRaw,
                         subjectID: $0.subjectID, subjectText: $0.subjectText, answer: $0.answer,
                         outcome: $0.outcomeRaw, source: $0.sourceRaw, language: $0.languageRaw,
                         askedAt: $0.askedAt, answeredAt: $0.answeredAt, writingSeconds: $0.writingSeconds)
                }),
            journalEntries: try JournalEntries.all(in: context).sorted { ($0.dayKey, $0.createdAt) < ($1.dayKey, $1.createdAt) }.map {
                JournalEntryRow(dayKey: $0.dayKey, blocks: $0.blocks, createdAt: $0.createdAt,
                                updatedAt: $0.updatedAt, doneAt: $0.doneAt)
            })
    }

    public static func data(_ context: ModelContext, seeds: Seeds? = nil, now: Date = Date()) throws -> Data {
        try encode(snapshot(context, seeds: seeds, now: now))
    }

    public static func encode(_ snapshot: Snapshot) throws -> Data {
        let encoder = JSONEncoder()
        // Sorted for a stable file, not indented: the indentation was about a third of its size.
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    /// The other half of `encode`, kept beside it so the two date strategies can't drift apart.
    public static func decode(_ data: Data) throws -> Snapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Snapshot.self, from: data)
    }

    /// `LifeRPG-2026-09-18.json`.
    public static func filename(now: Date = Date(), in timeZone: TimeZone = .current) -> String {
        "LifeRPG-\(now.dayKey(in: timeZone)).json"
    }
}
