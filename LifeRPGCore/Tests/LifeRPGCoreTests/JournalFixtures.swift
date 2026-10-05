import Foundation
import SwiftData
@testable import LifeRPGCore

/// Plain rows for journal tests, built without a store: the planner and the signals are pure
/// functions of rows, so a worked day is just a handful of them.
enum JournalFixtures {
    static let day = "2026-09-18"

    static func quest(_ text: String, on dayKey: String = day, done: Bool = true, hour: Int = 10,
                      variant: String? = nil, replaced: Bool = false) -> DailyQuest {
        let q = DailyQuest()
        q.dayKey = dayKey
        q.textSnapshot = text
        q.variantSnapshot = variant
        q.replaced = replaced
        if done {
            q.points = 10
            q.completedAt = Fixtures.date(dayKey, hour: hour)
        }
        return q
    }

    static func routineDone(_ text: String, on dayKey: String = day, hour: Int = 11) -> RoutineOccurrence {
        let o = RoutineOccurrence()
        o.textSnapshot = text
        o.dueDayKey = dayKey
        o.completedDayKey = dayKey
        o.completedAt = Fixtures.date(dayKey, hour: hour)
        return o
    }

    static func occurrence(_ text: String, due: String, skipped: Bool = false, completed: String? = nil,
                           routineID: UUID? = nil) -> RoutineOccurrence {
        let o = RoutineOccurrence()
        o.textSnapshot = text
        o.dueDayKey = due
        o.skipped = skipped
        o.completedDayKey = completed
        o.routineID = routineID
        return o
    }

    /// The `skip` entry `Overdue` books against an occurrence it gave up on.
    static func skipEntry(for o: RoutineOccurrence, on dayKey: String) -> LedgerEntry {
        let e = LedgerEntry()
        e.kind = Economy.Kind.skip.rawValue
        e.dayKey = dayKey
        e.refID = o.id
        return e
    }

    static func rating(of id: UUID, _ value: Int, on dayKey: String = day, hour: Int = 12) -> QuestRating {
        let r = QuestRating()
        r.questID = id
        r.rating = value
        r.dayKey = dayKey
        r.timestamp = Fixtures.date(dayKey, hour: hour)
        return r
    }

    static func context(tier: Tier, on dayKey: String = day) -> DailyContext {
        let c = DailyContext()
        c.dayKey = dayKey
        c.tier = tier
        return c
    }

    static func signals(tier: Tier = .normal, quests: [DailyQuest] = [], occurrences: [RoutineOccurrence] = [],
                        ratings: [QuestRating] = [], ledger: [LedgerEntry] = [], flexible: Set<UUID> = [],
                        on dayKey: String = day) -> JournalSignals {
        JournalSignals(dayKey: dayKey, quests: quests, occurrences: occurrences,
                       context: context(tier: tier, on: dayKey), ratings: ratings,
                       ledger: ledger, flexible: flexible, timeZone: Fixtures.tokyo)
    }

    static func turn(_ kind: JournalPromptKind, _ answer: String = "fine", index: Int = 0, on dayKey: String = day,
                     outcome: JournalOutcome = .answered, hour: Int = 22) -> JournalTurn {
        let t = JournalTurn()
        t.dayKey = dayKey
        t.index = index
        t.kind = kind
        t.questionText = "question"
        t.answer = answer
        t.outcome = outcome
        t.answeredAt = Fixtures.date(dayKey, hour: hour)
        return t
    }

    /// The free-writing turn: a closing turn with no question and no prompt id.
    static func freeWriting(_ answer: String, index: Int = 0, on dayKey: String = day, hour: Int = 22,
                            writingSeconds: Int = 0) -> JournalTurn {
        let t = turn(.closing, answer, index: index, on: dayKey, hour: hour)
        t.questionText = ""
        t.promptID = ""
        t.writingSeconds = writingSeconds
        return t
    }
}

/// Turn rows written the way the build before entries wrote them, for the tests of what is kept:
/// the migration, the turn export and import, the store audit. The writer itself is gone from Core.
enum TurnRows {
    @discardableResult
    static func record(_ context: ModelContext, dayKey: String, kind: JournalPromptKind, promptID: String = "",
                       question: String, subject: JournalSubject? = nil, answer: String = "",
                       outcome: JournalOutcome = .answered, source: JournalSource = .template,
                       language: JournalLanguage, askedAt: Date, answeredAt: Date) throws -> JournalTurn {
        let row = JournalTurn()
        row.dayKey = dayKey
        row.index = (try turns(on: dayKey, in: context).last?.index ?? -1) + 1
        row.kind = kind
        row.promptID = promptID
        row.questionText = question
        row.subjectKind = subject?.kind
        row.subjectID = subject?.id
        row.subjectText = subject?.text ?? ""
        row.answer = answer
        row.outcome = outcome
        row.source = source
        row.language = language
        row.askedAt = askedAt
        row.answeredAt = answeredAt
        context.insert(row)
        return row
    }

    /// The free-writing turn: a closing turn with no question and no prompt id, at the day's next index.
    @discardableResult
    static func freeWriting(_ context: ModelContext, _ text: String, on dayKey: String, at now: Date,
                            writingSeconds: Int = 0) throws -> JournalTurn {
        let row = try record(context, dayKey: dayKey, kind: .closing, question: "", answer: text,
                             language: .en, askedAt: now, answeredAt: now)
        row.writingSeconds = writingSeconds
        return row
    }

    static func turns(on dayKey: String, in context: ModelContext) throws -> [JournalTurn] {
        try context.fetch(FetchDescriptor<JournalTurn>(predicate: #Predicate { $0.dayKey == dayKey },
                                                       sortBy: [SortDescriptor(\.index)]))
    }
}
