import LifeRPGCore
import SwiftUI

/// Every state of the Today cards, from sample rows run through the same Core builders the page
/// uses, so light, dark and the largest text size can all be looked at without time travel.
struct TodayCardsGallery: View {
    private static let friday = "2026-10-02"

    @State private var demoDone = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("Level card") {
                LevelCardView(state: level(balance: 1240, streak: 12, goal: Self.goalOpen)) {}
                LevelCardView(state: level(balance: -35, streak: 0, tier: .low, goal: nil)) {}
                LevelCardView(state: level(balance: 950, streak: 3, goal: Self.goalReady)) {}
            }
            group("Epic: open, extended, done, long title (tap a card to expand)") {
                EpicCardView(state: epic(), actions: epicMenu) {}
                EpicCardView(state: epic(extensions: 1, today: "2026-10-06"), actions: epicMenu) {}
                EpicCardView(state: epic(points: 112)) {}
                EpicCardView(state: epic(title: "Get a side project to demo-able state and show it to three people",
                                         extensions: 1, today: "2026-10-06", url: "https://example.com/e"),
                             actions: epicMenu) {}
            }
            group("Routines: open, with strikes, overdue, light version, done, skipped") {
                RoutineRowView(state: routine("Take out the trash", base: 5), actions: routineMenu) {}
                RoutineRowView(state: routine("Incline walk 30 min", routine: fixedRoutine),
                               actions: routineMenu) {}
                RoutineRowView(state: routine("Cat grooming", base: 15, due: "2026-10-01", placement: .overdue),
                               actions: routineMenu) {}
                RoutineRowView(state: lightRoutine, actions: routineMenu) {}
                RoutineRowView(state: routine("Strength session", routine: flexibleRoutine,
                                              due: "2026-09-30", placement: .thisWeek),
                               actions: [replaceItem]) {}
                RoutineRowView(state: routine("Water the plants", done: 15)) {}
                RoutineRowView(state: routine("Call the dentist", skipped: true)) {}
                RoutineRowView(state: routine("Call mum", adHoc: true), actions: routineMenu) {}
                RoutineRowView(state: routine("Change bedsheets", base: 15, adHoc: true, noGate: true),
                               actions: routineMenu) {}
                RoutineRowView(state: routine("A fairly long routine name that has to wrap onto several lines",
                                              base: 25, due: "2026-10-01", placement: .overdue),
                               actions: routineMenu) {}
            }
            group("Quest tiles: easy, medium, hard, done") {
                TileGrid {
                    QuestTileView(state: tile("Write a journal entry", .easy, variant: "A view I've recently changed"),
                                  actions: tileMenu) {}
                    QuestTileView(state: tile("Walk 8,000 steps", .medium, url: "https://example.com"),
                                  actions: tileMenu) {}
                    QuestTileView(state: tile("Send one cold email to someone you admire", .hard),
                                  actions: tileMenu) {}
                    QuestTileView(state: tile("Drink 2L of water", .easy, points: 11)) {}
                    QuestTileView(state: tile("Sort the mail", .easy, tier: .low), actions: tileMenu) {}
                }
            }
            group("Complete demo") {
                TileGrid {
                    QuestTileView(state: tile("Stretch for ten minutes", .easy, points: demoDone ? 12 : nil)) {
                        demoDone = true
                    }
                    Button("Reset") { demoDone = false }
                        .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .lrCard(.surface, radius: LR.Radius.tile)
                }
            }
            group("Hidden quest, gate, micro-actions") {
                QuestTileView(state: tile("Write a thank-you note", .medium, hidden: true)) {}
                HiddenGateTile(unlocked: true) {}
                HiddenGateTile(unlocked: false) {}
                MicroGroupTileView(state: trio(ticked: 1), actions: [rerollItem]) { _ in }
                MicroGroupTileView(state: trio(ticked: 0)) { _ in }
                MicroGroupTileView(state: trio(ticked: 3, points: 12)) { _ in }
            }
            group("Records") {
                ReplacedRowView(state: replaced(.cancelled))
                ReplacedRowView(state: replaced(.adHoc))
                RecordRowView(title: "Pay the credit card", caption: "Due 2026-09-29", secondary: true) {
                    PillLabel(text: "−20", style: .clay)
                }
                RecordRowView(title: "Incline walk", caption: "1/2 this week · next due 2026-10-03",
                              doodle: .sneaker) {
                    PillLabel(text: "20")
                }
                BannerView(title: "Today could not be generated", message: "The pool is empty.")
            }
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LR.Spacing.gridGap) {
            Text(title).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
            content()
        }
    }

    // MARK: sample rows

    private static let goalOpen = SavingsGoal.Progress(name: "AirPods Pro", price: 900, balance: 640,
                                                       fraction: 640.0 / 900.0, weeksLeft: 3)
    private static let goalReady = SavingsGoal.Progress(name: "AirPods Pro", price: 900, balance: 950,
                                                        fraction: 1, weeksLeft: 0)

    private func level(balance: Int, streak: Int, tier: Tier = .normal,
                       goal: SavingsGoal.Progress?) -> LevelCardState {
        LevelCardState(totalEarned: 3528, balance: balance, streak: streak, tier: tier, randomSlots: 4, goal: goal)
    }

    private func epic(title: String = "Ship the MCP eval set v1", extensions: Int = 0,
                      today: String = friday, points: Int? = nil, url: String? = nil) -> EpicCardState {
        let e = DailyQuest()
        e.slot = .epic
        e.dayKey = "2026-09-28"
        e.textSnapshot = title
        e.extensionCount = extensions
        e.points = points
        e.launchURLSnapshot = url
        return EpicCardState(e, today: today, tier: .normal, level: 8)
    }

    private func quest(_ text: String, _ slot: Difficulty, points: Int? = nil) -> DailyQuest {
        let q = DailyQuest()
        q.dayKey = Self.friday
        q.slot = slot
        q.textSnapshot = text
        q.points = points
        return q
    }

    private func tile(_ text: String, _ slot: Difficulty, points: Int? = nil, variant: String? = nil,
                      url: String? = nil, hidden: Bool = false, tier: Tier = .normal) -> QuestCardState {
        let q = quest(text, slot, points: points)
        q.variantSnapshot = variant
        q.launchURLSnapshot = url
        q.isHiddenSlot = hidden
        return QuestCardState(q, tier: tier)
    }

    private func trio(ticked: Int, points: Int? = nil) -> QuestCardState {
        let q = quest("", .trivial, points: points)
        q.trivialGroup = ["Floss", "Make the bed", "Water the plant"]
        q.trivialVariants = ["", "", "the fern"]
        q.trivialDone = (0..<3).map { $0 < ticked }
        return QuestCardState(q, tier: .normal)
    }

    private func replaced(_ reason: ReplacedReason) -> ReplacedRowState {
        let q = quest("Sort the mail", .easy)
        q.replaced = true
        q.replacedReason = reason
        return ReplacedRowState(q)
    }

    private var fixedRoutine: RoutineTask {
        let r = RoutineTask()
        r.kind = .weekly
        r.spec = "WED,SAT"
        r.autoVerifyRule = "calendar:workout"
        return r
    }

    private var flexibleRoutine: RoutineTask {
        let r = RoutineTask()
        r.flexibleWithinWeek = true
        r.weeklyTarget = 2
        return r
    }

    private func occurrence(_ text: String, base: Int, due: String) -> RoutineOccurrence {
        let o = RoutineOccurrence()
        o.textSnapshot = text
        o.basePoints = base
        o.dueDayKey = due
        o.weekKey = "2026-W40"
        o.routineID = UUID()
        return o
    }

    private func routine(_ text: String, base: Int = 20, routine: RoutineTask? = nil,
                         due: String = friday, placement: RoutineRowState.Placement = .today,
                         done: Int? = nil, skipped: Bool = false, adHoc: Bool = false,
                         noGate: Bool = false, tier: Tier = .normal) -> RoutineRowState {
        let o = occurrence(text, base: base, due: due)
        if done != nil { o.completedDayKey = Self.friday; o.awardedPoints = done }
        o.skipped = skipped
        if adHoc { o.routineID = nil }
        if noGate { o.countsForClear = false }
        return RoutineRowState(o, placement: placement, routine: routine,
                               flexible: routine?.flexibleWithinWeek ?? false,
                               today: Self.friday, tier: tier, level: 1, quests: [], occurrences: [o])
    }

    private var lightRoutine: RoutineRowState {
        let o = occurrence("Strength session", base: 20, due: Self.friday)
        o.degradedTextSnapshot = "Stretch 15 min"
        o.degradedBasePoints = 10
        o.usedDegraded = true
        return RoutineRowState(o, placement: .today, routine: nil, flexible: false, today: Self.friday,
                               tier: .low, level: 1, quests: [], occurrences: [o])
    }

    // MARK: sample menus

    private var rerollItem: CardAction { CardAction(title: "Reroll · 10", systemImage: "dice") {} }
    private var replaceItem: CardAction { CardAction(title: "Replace", systemImage: "arrow.triangle.swap") {} }
    private var tileMenu: [CardAction] {
        [rerollItem, CardAction(title: "Cancel", systemImage: "xmark", isEnabled: false) {}, replaceItem]
    }
    private var routineMenu: [CardAction] {
        [CardAction(title: "Cancel · 200", systemImage: "xmark") {}, replaceItem]
    }
    private var epicMenu: [CardAction] {
        [CardAction(title: "Reroll · 40", systemImage: "dice") {},
         CardAction(title: "Extend · 50", systemImage: "calendar.badge.plus") {}, replaceItem]
    }
}
