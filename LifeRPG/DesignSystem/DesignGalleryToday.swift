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
            group("Quest rows: easy, medium, hard, done, low day (tap Open link in the menu)") {
                QuestRowView(state: tile("Write a journal entry", .easy, variant: "A view I've recently changed"),
                             actions: tileMenu) {}
                QuestRowView(state: tile("Walk 8,000 steps", .medium, url: "https://example.com"),
                             actions: tileMenu) {}
                QuestRowView(state: tile("Send one cold email to someone you admire", .hard),
                             actions: tileMenu) {}
                QuestRowView(state: tile("Drink 2L of water", .easy, points: 11)) {}
                QuestRowView(state: tile("Sort the mail", .easy, tier: .low), actions: tileMenu) {}
            }
            group("Complete demo") {
                QuestRowView(state: tile("Stretch for ten minutes", .easy, points: demoDone ? 12 : nil)) {
                    demoDone = true
                }
                Button("Reset") { demoDone = false }
                    .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .lrCard(.surface, radius: LR.Radius.row)
            }
            group("Hidden quest, gate, micro-actions") {
                QuestRowView(state: tile("Write a thank-you note", .medium, hidden: true)) {}
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

/// The Completed stack in each state it takes on Today, from sample rows run through the same Core
/// rule the page uses.
struct CompletedStackGallery: View {
    private static let friday = "2026-10-02"
    private static let base = Date(timeIntervalSince1970: 1_790_000_000)

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            demo("Collapsed: four done", expanded: false, state: Self.state(Self.four))
            demo("Expanded: every kind of row", expanded: true, state: Self.state(Self.every))
            demo("One item", expanded: false, state: Self.state([Self.quest("Listen to a stand-up comedy clip", .easy, points: 6, minute: 1)]))
            demo("Only the epic", expanded: false, state: Self.state([Self.epic(points: 112, minute: 1)]))
        }
    }

    private func demo(_ title: String, expanded: Bool, state: CompletedStackState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
            CompletedStackDemo(state: state, startsExpanded: expanded)
        }
    }

    private struct CompletedStackDemo: View {
        let state: CompletedStackState
        @State private var expanded: Bool

        init(state: CompletedStackState, startsExpanded: Bool) {
            self.state = state
            _expanded = State(initialValue: startsExpanded)
        }

        var body: some View { CompletedStackView(state: state, expanded: $expanded) }
    }

    private enum Row {
        case quest(DailyQuest)
        case routine(RoutineOccurrence)
    }

    private static func state(_ rows: [Row]) -> CompletedStackState {
        var quests: [DailyQuest] = []
        var occurrences: [RoutineOccurrence] = []
        for row in rows {
            switch row {
            case .quest(let q): quests.append(q)
            case .routine(let o): occurrences.append(o)
            }
        }
        return CompletedStackState(quests: quests, occurrences: occurrences, today: friday,
                                   tier: .normal, level: 1) { o in
            RoutineRowState(o, placement: .today, routine: nil, flexible: false, today: friday,
                            tier: .normal, level: 1, quests: quests, occurrences: occurrences)
        }
    }

    private static var four: [Row] {
        [quest("Browse a supermarket without buying anything", .medium, points: 17, minute: 40),
         routine("Workout: running", points: 25, minute: 50),
         quest("Listen to a stand-up comedy clip", .easy, points: 6, minute: 30),
         epic(points: 112, minute: 10)]
    }

    private static var every: [Row] {
        [quest("Write a thank-you note", .medium, points: 40, minute: 90, hidden: true),
         group(points: 12, minute: 80),
         routine("Workout: running", points: 25, minute: 70),
         quest("Browse a supermarket without buying anything", .medium, points: 17, minute: 60),
         quest("Send one cold email to someone you admire", .hard, points: 31, minute: 50),
         epic(points: 112, minute: 10)]
    }

    private static func quest(_ text: String, _ slot: Difficulty, points: Int, minute: Int,
                              hidden: Bool = false) -> Row {
        let q = DailyQuest()
        q.dayKey = friday
        q.slot = slot
        q.textSnapshot = text
        q.points = points
        q.completedAt = base.addingTimeInterval(Double(minute) * 60)
        q.isHiddenSlot = hidden
        return .quest(q)
    }

    private static func group(points: Int, minute: Int) -> Row {
        let q = DailyQuest()
        q.dayKey = friday
        q.slot = .trivial
        q.trivialGroup = ["Floss", "Make the bed", "Water the plant"]
        q.trivialDone = [true, true, true]
        q.points = points
        q.completedAt = base.addingTimeInterval(Double(minute) * 60)
        return .quest(q)
    }

    private static func routine(_ text: String, points: Int, minute: Int) -> Row {
        let o = RoutineOccurrence()
        o.textSnapshot = text
        o.basePoints = points
        o.dueDayKey = friday
        o.weekKey = "2026-W40"
        o.routineID = UUID()
        o.completedDayKey = friday
        o.awardedPoints = points
        o.completedAt = base.addingTimeInterval(Double(minute) * 60)
        return .routine(o)
    }

    private static func epic(points: Int, minute: Int) -> Row {
        let e = DailyQuest()
        e.slot = .epic
        e.dayKey = "2026-09-28"
        e.textSnapshot = "Get a side project to demo-able state"
        e.points = points
        e.completedAt = base.addingTimeInterval(Double(minute) * 60)
        return .quest(e)
    }
}

/// The Ahead section in the states it takes on Today, from sample routines run through the same
/// Core builder the page uses.
struct AheadStackGallery: View {
    private static let friday = "2026-10-02"

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            demo("Collapsed: open, done ahead and a candidate, with Sunday's bill",
                 expanded: false, state: Self.state(low: false))
            demo("Expanded", expanded: true, state: Self.state(low: false))
            demo("A low day: a candidate pays its lighter versions", expanded: false, state: Self.state(low: true))
            demo("One candidate", expanded: false, state: Self.single)
        }
    }

    private func demo(_ title: String, expanded: Bool, state: AheadState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
            AheadDemo(state: state, startsExpanded: expanded)
        }
    }

    private struct AheadDemo: View {
        let state: AheadState
        @State private var expanded: Bool

        init(state: AheadState, startsExpanded: Bool) {
            self.state = state
            _expanded = State(initialValue: startsExpanded)
        }

        var body: some View {
            StackedCards(title: "Ahead this week", summary: state.summary, badge: state.billText,
                         accessibilityLabel: state.accessibilityLabel,
                         items: state.items, expanded: $expanded) { item in
                switch item {
                case .routine(let row): RoutineRowView(state: row, onComplete: {})
                case .candidate(let row): AheadCandidateRowView(state: row) {}
                }
            }
        }
    }

    private static func routine(_ text: String, base: Int, spec: String = "SAT", target: Int = 1) -> RoutineTask {
        let r = RoutineTask()
        r.text = text
        r.spec = spec
        r.basePoints = base
        r.weeklyTarget = target
        r.flexibleWithinWeek = true
        return r
    }

    private static func occurrence(_ r: RoutineTask, due: String, paid: Int? = nil) -> RoutineOccurrence {
        let o = RoutineOccurrence()
        o.textSnapshot = r.text
        o.basePoints = r.basePoints
        o.dueDayKey = due
        o.weekKey = "2026-W40"
        o.routineID = r.id
        if let paid { o.completedDayKey = friday; o.awardedPoints = paid }
        return o
    }

    private static func state(_ routines: [RoutineTask], _ occurrences: [RoutineOccurrence],
                              tier: Tier = .normal) -> AheadState {
        AheadState(routines: routines, occurrences: occurrences,
                   flexible: Set(routines.filter(\.flexibleWithinWeek).map(\.id)),
                   today: friday, tier: tier) { o, placement in
            RoutineRowState(o, placement: placement, routine: routines.first { $0.id == o.routineID },
                            flexible: true, today: friday, tier: tier, level: 1,
                            quests: [], occurrences: occurrences)
        }
    }

    private static func state(low: Bool) -> AheadState {
        let strength = routine("Strength session", base: 20)
        let run = routine("Workout: running", base: 25)
        let yoga = routine("Yoga", base: 10, spec: "SUN")
        let light = routine("Stretch 15 min", base: 20, spec: "SAT")
        light.flexibleWithinWeek = false
        let weights = routine("Workout: weight training", base: 40, spec: "SUN")
        weights.downgradeIDs = [light.id]
        return state([strength, run, yoga, light, weights],
                     [occurrence(strength, due: "2026-09-30"), occurrence(run, due: "2026-10-03", paid: 25)],
                     tier: low ? .low : .normal)
    }

    private static var single: AheadState {
        state([routine("Incline walk 30 min", base: 20, spec: "SAT", target: 2)], [])
    }
}

/// The Today page's one card, drawn statically at every phase, plus a button that plays the real
/// overlay with sample rows and a `⋯` button with the priced rows (one blocked) that raises the
/// real popover.
struct PopupsGallery: View {
    private static let friday = "2026-10-02"
    private static let breakdown = Scoring.breakdown(slot: .medium, isTrivialGroup: false, isHidden: false,
                                                     tier: .normal, awarded: 18)

    @State private var playing = false
    @State private var lastRating: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button("Play the flow on a quest") { playing = true }
                .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .lrCard(.surface, radius: LR.Radius.row)
            if let lastRating {
                Text("Last rating: \(RatingScale.label(for: lastRating))")
                    .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
            }
            phase("Ask: a quest", Self.quest, .ask(ask))
            phase("Ask: a routine, fixed payout and no reel", MomentHeader(Self.routine("Incline walk, 30 minutes", base: 20)),
                  .ask(MomentAsk(lead: .fixed(pill: "+20"), choices: [.init(title: "Complete") {}], notYet: {})))
            phase("Paid: a routine, no roll", MomentHeader(Self.routine("Incline walk, 30 minutes", base: 20)),
                  .payout(MomentPayout(id: UUID(), fixed: 20) { _ in }), stage: .rate, picked: 1)
            phase("Ask: the epic", MomentHeader(Self.epic), .ask(ask))
            phase("Rolling", Self.quest, .payout(payout), stage: .rolling, clock: .frozen(0.55))
            phase("Landed", Self.quest, .payout(payout), stage: .landed)
            phase("Landed: a fixed group, nothing rolled", MomentHeader(doodle: .sparkle, tint: .trivial,
                                                                       title: "Micro-actions",
                                                                       subtitle: "Floss · Eye drops · Old song"),
                  .payout(MomentPayout(id: UUID(),
                                       breakdown: Scoring.breakdown(slot: .easy, isTrivialGroup: true,
                                                                    isHidden: false, tier: .normal, awarded: 12)) { _ in }),
                  stage: .landed)
            phase("Rate, one picked", Self.quest, .payout(payout), stage: .rate, picked: 1)
            phase("Ask: low day, light version",
                  MomentHeader(doodle: .forText("Workout: weight training"), tint: .routine,
                               title: "Workout: weight training", subtitle: "Ahead of schedule"),
                  .ask(MomentAsk(lead: .fixed(pill: nil),
                                 choices: [.init(title: "Did the original", pill: "+20") {},
                                           .init(title: "Did a lighter version", pill: "+10–14", outlined: true) {}],
                                 footnote: "Lighter: Stretch 15 min / Walk 20 min", notYet: {})))
            phase("Spend: reroll", Self.spendHeader,
                  .notice(MomentNotice(message: "Swap it for a different M for 30 coins. The next reroll of this slot today costs more.",
                                       primary: "Spend 30", quiet: "Not yet", confirm: {}, dismiss: {})))
            phase("Can't reroll", MomentHeader(doodle: .forText("Walk by the river"), tint: .medium,
                                               title: "Can't reroll", subtitle: "Walk by the river"),
                  .notice(MomentNotice(message: "Nothing else in the pool. Nothing was charged.",
                                       primary: "OK", confirm: {}, dismiss: {})))
            phase("Level-up moment", MomentHeader(doodle: .sparkle, tint: nil, title: "Level 7"),
                  .notice(MomentNotice(message: "Unlocked:\n· A third free reroll each day",
                                       primary: "Nice", confirm: {}, dismiss: {})))
            HStack {
                Text("The ⋯ popover, a blocked row").lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                Spacer()
                CardMenuButton(actions: Self.menu)
            }
            .padding(.leading, 16)
            .frame(minHeight: 44)
            .lrCard(.surface, radius: LR.Radius.row)
        }
        .fullScreenCover(isPresented: $playing) { PlayDemo(lastRating: $lastRating) }
    }

    private var ask: MomentAsk { MomentAsk(choices: [.init(title: "Complete") {}], notYet: {}) }

    private var payout: MomentPayout { MomentPayout(id: UUID(), breakdown: Self.breakdown) { _ in } }

    private func phase(_ title: String, _ header: MomentHeader, _ content: MomentContent,
                       stage: MomentStage = .rolling, clock: ReelClock = .frozen(0),
                       picked: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
            MomentCardFace(header: header, content: content, stage: stage,
                           frames: [14, 27, 12, 22, 30, 16, 25, 13, 21, 28, 15, 23, 29, 17, 24, 20],
                           clock: clock, picked: picked)
                .frame(maxWidth: 320)
                .frame(maxWidth: .infinity)
        }
    }

    /// The real overlay on a throwaway page: Complete turns the card into the payout in place.
    private struct PlayDemo: View {
        @Binding var lastRating: Int?
        @Environment(\.dismiss) private var dismiss
        @State private var completed = false
        @State private var payoutID = UUID()

        var body: some View {
            ZStack {
                LR.Color.canvas.ignoresSafeArea()
                HandText("The page behind", .hand).foregroundStyle(LR.Color.accent)
                MomentCard(header: PopupsGallery.quest, content: content)
            }
        }

        private var content: MomentContent {
            completed
                ? .payout(MomentPayout(id: payoutID, breakdown: PopupsGallery.breakdown) { rating in
                    lastRating = rating
                    dismiss()
                })
                : .ask(MomentAsk(choices: [.init(title: "Complete") {
                    withAnimation(.easeOut(duration: 0.2)) { completed = true }
                }], notYet: { dismiss() }))
        }
    }

    private static var quest: MomentHeader {
        MomentHeader(questState("Walk by the river", .medium, variant: "20 minutes"))
    }

    private static var spendHeader: MomentHeader {
        MomentHeader(doodle: .forText("Walk by the river"), tint: .medium, title: "Reroll?",
                     subtitle: "Walk by the river")
    }

    private static var menu: [CardAction] {
        [CardAction(title: "Reroll · 30", systemImage: "dice", label: "Reroll", trailing: "30 coins") {},
         CardAction(title: "Cancel", systemImage: "xmark", isEnabled: false, label: "Cancel", trailing: "120 coins") {},
         CardAction(title: "Replace", systemImage: "arrow.triangle.swap") {}]
    }

    private static func questState(_ text: String, _ slot: Difficulty, variant: String?) -> QuestCardState {
        let q = DailyQuest()
        q.dayKey = friday
        q.slot = slot
        q.textSnapshot = text
        q.variantSnapshot = variant
        return QuestCardState(q, tier: .normal)
    }

    private static func routine(_ text: String, base: Int) -> RoutineRowState {
        let o = RoutineOccurrence()
        o.textSnapshot = text
        o.basePoints = base
        o.dueDayKey = friday
        o.weekKey = "2026-W40"
        o.routineID = UUID()
        return RoutineRowState(o, placement: .today, routine: nil, flexible: false, today: friday,
                               tier: .normal, level: 1, quests: [], occurrences: [o])
    }

    private static var epic: EpicCardState {
        let e = DailyQuest()
        e.slot = .epic
        e.dayKey = "2026-09-28"
        e.textSnapshot = "Get a side project to demo-able state"
        return EpicCardState(e, today: friday, tier: .normal, level: 8)
    }
}
