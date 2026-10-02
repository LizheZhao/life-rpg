import Foundation
import SwiftData

/// Everything derived from the ledger. Balance is **always** a sum over `LedgerEntry` — there is
/// no cached balance field, and adding one is how the two numbers start disagreeing.
public enum Economy {
    /// Ledger kinds. Spending and penalties are stored as negative `points`.
    ///
    /// `freeze` is the one entry booked to a day other than the one it happened on: its `dayKey`
    /// is the missed day it covers (`Streak.frozenDayKeys`), and `timestamp` is when it was bought.
    ///
    /// `streak` is a milestone bonus (`StreakMilestone`); its `note` names the threshold it paid.
    public enum Kind: String, CaseIterable, Sendable {
        case quest, routine, redeem, reroll, penalty, skip, adjust, grant, freeze, streak
    }

    /// Current balance; may be negative, which is displayed in red rather than clamped.
    ///
    /// The array overloads exist so the today page can pass the rows its `@Query` already holds,
    /// instead of re-implementing the sums beside the HUD. Two copies of "what counts" is how the
    /// number on screen and the number in Core start disagreeing.
    public static func balance(_ entries: [LedgerEntry]) -> Int {
        entries.reduce(0) { $0 + $1.points }
    }

    /// The same sum over an export's rows — what an import's confirmation says the balance will be.
    public static func balance(_ entries: [JSONExport.Ledger]) -> Int {
        entries.reduce(0) { $0 + $1.points }
    }

    public static func balance(_ context: ModelContext) throws -> Int {
        balance(try context.fetch(FetchDescriptor<LedgerEntry>()))
    }

    /// Cumulative **earned** points: positive entries only, so spending doesn't drop the level —
    /// and not the opening grant, which was given rather than earned. A gift that bought a level
    /// would make the number mean "how long have you had the app" instead of "how much have you
    /// done", which is the one thing a level is for.
    public static func totalEarned(_ entries: [LedgerEntry]) -> Int {
        entries
            .filter { $0.kind != Kind.grant.rawValue }
            .reduce(0) { $0 + max(0, $1.points) }
    }

    public static func totalEarned(_ context: ModelContext) throws -> Int {
        totalEarned(try context.fetch(FetchDescriptor<LedgerEntry>()))
    }

    /// `level = floor(sqrt(total / 60)) + 1` (`PLAN.md` §6).
    public static func level(totalEarned: Int) -> Int {
        Int((Double(max(0, totalEarned)) / 60.0).squareRoot().rounded(.down)) + 1
    }

    /// The earned total at which `level` starts: `60 × (level − 1)²`.
    public static func earnedNeeded(forLevel level: Int) -> Int {
        let n = max(0, level - 1)
        return 60 * n * n
    }

    /// The level in force right now — what every perk (`Perks`) is priced against.
    public static func level(_ entries: [LedgerEntry]) -> Int {
        level(totalEarned: totalEarned(entries))
    }

    public static func level(_ context: ModelContext) throws -> Int {
        level(totalEarned: try totalEarned(context))
    }

    /// Points still needed for the next level, for the HUD's progress line.
    public static func pointsToNextLevel(totalEarned: Int) -> Int {
        let next = level(totalEarned: totalEarned)          // level n+1 starts at 60 × n²
        return max(0, 60 * next * next - max(0, totalEarned))
    }

    /// How far through the current level `totalEarned` is, 0 up to (not including) 1. The level
    /// card's bar and dots read this so the view never does the division itself.
    public static func levelProgress(totalEarned: Int) -> Double {
        let (done, span) = levelSpan(totalEarned: totalEarned)
        return Double(done) / Double(span)
    }

    /// Filled dots of a `count`-dot grid: the floor of progress, done in integers because
    /// `0.05 × 20` is not exactly 1 in floating point and a dot must light on the exact point.
    public static func levelDots(totalEarned: Int, count: Int = 20) -> Int {
        let (done, span) = levelSpan(totalEarned: totalEarned)
        return done * count / span
    }

    private static func levelSpan(totalEarned: Int) -> (done: Int, span: Int) {
        let total = max(0, totalEarned)
        let current = level(totalEarned: total)
        let start = earnedNeeded(forLevel: current)
        return (total - start, earnedNeeded(forLevel: current + 1) - start)
    }

    /// The opening balance. Coins are only earned by doing things, so a brand new store starts at
    /// zero — which means the first reroll is unaffordable and the economy has nothing in it until
    /// several days have gone by. This is the float that gets it moving.
    ///
    /// Granted **once, ever**, keyed on a `grant` entry already existing rather than on the ledger
    /// being empty: a JSON import brings its own grant along with the rest of the history, and a
    /// second one would quietly mint another 100.
    public static let startingBalance = 100

    @discardableResult
    public static func grantStartingBalanceIfNeeded(_ context: ModelContext,
                                                    dayKey: String,
                                                    amount: Int = startingBalance,
                                                    now: Date = Date()) throws -> LedgerEntry? {
        let kind = Kind.grant.rawValue
        let existing = try context.fetchCount(
            FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.kind == kind }))
        guard existing == 0 else { return nil }
        let entry = record(context, kind: .grant, points: amount, dayKey: dayKey,
                           note: "Starting balance", now: now)
        try context.save()
        return entry
    }

    @discardableResult
    public static func record(_ context: ModelContext,
                              kind: Kind,
                              points: Int,
                              dayKey: String,
                              refID: UUID? = nil,
                              note: String = "",
                              now: Date = Date()) -> LedgerEntry {
        let entry = LedgerEntry()
        entry.kind = kind.rawValue
        entry.points = points
        entry.dayKey = dayKey
        entry.refID = refID
        entry.note = note
        entry.timestamp = now
        context.insert(entry)
        return entry
    }
}
