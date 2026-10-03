import LifeRPGCore
import SwiftData
import SwiftUI

/// The daily page: level card, epic, routines (overdue pinned on top), today's random slots, and
/// the hidden quest once the day is cleared.
///
/// There is no undo anywhere on this page — completion writes a ledger entry and starts the
/// template's cooldown, both final. That is why every completion and every purchase asks first.
/// It asks once, in one centered card (`MomentCard`), and that same card then shows the payout,
/// so nothing is stacked after the confirmation.
struct TodayView: View {
    let today: String
    let generationError: String?
    /// Set while the card is up, so the floating tab bar (which sits above this page) fades out
    /// under the dim.
    var hidesTabBar: Binding<Bool> = .constant(false)

    @Environment(\.modelContext) private var context

    // Small tables (a handful of rows per day), so the whole set is queried and filtered here
    // rather than rebuilding a predicate every time the day rolls over.
    @Query(sort: \DailyQuest.dayKey) private var allQuests: [DailyQuest]
    @Query private var ledger: [LedgerEntry]
    @Query private var contexts: [DailyContext]
    @Query private var occurrences: [RoutineOccurrence]
    @Query private var routines: [RoutineTask]
    @Query private var rewards: [Reward]

    /// What the one card is showing, or nil when it is down. Everything that needs an answer or an
    /// announcement goes through here, so two cards can never stack.
    @State private var overlay: Overlay?
    /// Local on purpose: collapsed on every launch, however it was left.
    @State private var completedExpanded = false
    /// Rows that have just been completed and still sit in their own section for a moment, so the
    /// check, the strikethrough and the "+N" finish where the tap was before the card moves into
    /// the Completed stack. A UI convenience, not data: after a relaunch it is simply empty.
    @State private var settling: Set<UUID> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Collapsed by default on weekdays: it lists every flexible routine still short this week,
    /// which is most of them early in the week, and none of it is today's work. Open by default on
    /// Saturday and Sunday, when whatever is left there is about to be settled.
    @AppStorage("aheadExpanded") private var aheadExpanded = false
    /// The day the section was last toggled by hand: that day, the hand wins over the weekend default.
    @AppStorage("aheadToggledOn") private var aheadToggledOn = ""
    /// The slot whose "Replace" swipe action opened the ad-hoc sheet.
    @State private var replacing: DailyQuest?
    /// The routine whose "Replace" swipe action opened the ad-hoc sheet.
    @State private var replacingRoutine: RoutineOccurrence?
    /// The epic whose "Replace" swipe action opened its sheet.
    @State private var replacingEpic: DailyQuest?
    /// The + button: a routine added on top of the day, replacing nothing.
    @State private var adding = false
    @State private var actionError: String?
    @State private var showingTrack = false
    /// What has already been announced. A UI convenience, not data: losing it only shows a card
    /// once more. 0 = never announced, which on the first launch after an update lists the perks
    /// already unlocked.
    @AppStorage("announcedLevel") private var announcedLevel = 0
    @AppStorage("announcedStreakBonusAt") private var announcedStreakBonusAt: Double = 0

    /// A reroll that was refused only once it tried to draw (nothing else in the pool). It replaces
    /// the spend card's content in place.
    private struct RerollRefusal {
        let header: MomentHeader
        let reason: String
    }

    /// The card's one state. `ask` becomes `reveal` in place once the completion is written.
    private enum Overlay {
        case ask(PendingAction)
        case spend(Spend)
        case refusal(RerollRefusal)
        /// A level-up or streak milestone, shown once nothing else is up.
        case moment(Moment)
        case reveal(Roll)
    }

    private struct Moment {
        var title: String
        var message: String
        var level: Int
        var streakBonusAt: Double
    }

    /// A payout that has already happened and is already in the ledger, waiting to be described.
    private struct Roll: Identifiable {
        let id = UUID()
        var header: MomentHeader
        var amount: MomentPayout.Amount
        /// What the rating is filed under: the quest template, or the routine.
        var target: FeedbackTarget
        /// Carried so the rating can be filed against the exact completion that prompted it (the
        /// `DailyQuest` or the `RoutineOccurrence`), not just against the template.
        var questID: UUID?
        var templateID: UUID?
        var text: String
        var dayKey: String
    }

    /// Everything bought from a row's `⋯` menu. The rules and prices are Core's; this only says
    /// what the confirmation reads.
    private enum Spend {
        case reroll(DailyQuest)
        case extend(DailyQuest)
        case cancelQuest(DailyQuest)
        case cancelRoutine(RoutineOccurrence)

        var title: String {
            switch self {
            case .reroll: "Reroll?"
            case .extend: "Extend the epic?"
            case .cancelQuest, .cancelRoutine: "Cancel it?"
            }
        }
    }

    /// Priced with the level in force (`Perks`); a free reroll reads 0.
    private func cost(of spend: Spend) -> Int {
        switch spend {
        case .reroll(let q): Reroll.cost(for: q, level: level, freeUsedToday: freeRerollsUsed)
        case .extend: Epic.extensionCost
        case .cancelQuest(let q): Redemption.cancelCost(for: q.slot) ?? 0
        case .cancelRoutine: Redemption.cancelRoutineCost
        }
    }

    private func price(_ spend: Spend) -> String {
        let c = cost(of: spend)
        return c == 0 ? "free" : "\(c) coins"
    }

    private enum PendingAction {
        case quest(DailyQuest)
        case trivialItem(DailyQuest, Int)
        case routine(RoutineOccurrence)
        case ahead(RoutineTask)
    }

    private var todayContext: DailyContext? { contexts.first { $0.dayKey == today } }
    private var tier: Tier { todayContext?.tier ?? .normal }
    private var cycleDay: Int? { todayContext?.cycleDay }
    /// The day's measured state, as stored. Both completion scoring and the hidden draw read this
    /// same value — a hidden quest drawn under `normal` rules on a very-low day would hand out the
    /// hardest thing in the pool as the reward for a day you barely got through.
    private var inputs: DayInputs { DayInputs(tier: tier, cycleDay: cycleDay) }

    private var aheadOpen: Bool {
        aheadToggledOn == today ? aheadExpanded : (DayKey.isWeekend(today) || aheadExpanded)
    }

    /// Whether doing this routine ahead today would offer a lighter version — only on a low day,
    /// which the first three cycle days also are.
    private func offersLightVersion(_ routine: RoutineTask) -> Bool {
        tier.isLow && !Degrade.versions(of: routine, in: routines).isEmpty
    }

    private func lightVersionList(_ routine: RoutineTask) -> String {
        Degrade.versions(of: routine, in: routines).map(\.text).joined(separator: " / ")
    }

    /// Which slots an ad-hoc routine may take over is `AdHoc`'s rule.
    private var replaceableIDs: Set<UUID> { Set(AdHoc.replaceableSlots(quests, on: today).map(\.id)) }

    private var quests: [DailyQuest] { allQuests.filter { $0.dayKey == today } }
    private var currentEpic: DailyQuest? { Epic.current(allQuests, on: today) }
    /// Easy first, the way the composition table is written — the query itself has no order
    /// beyond `dayKey`, so without this the rows shuffle on every regeneration.
    private var randomQuests: [DailyQuest] {
        // A rerolled-away row is history, not today's work: the day detail shows it, this page doesn't.
        quests.filter { !$0.isHiddenSlot && $0.slot != .epic && !($0.replaced && $0.replacedReason == .rerolled) }
            .sorted { a, b in
                let ra = Difficulty.allCases.firstIndex(of: a.slot) ?? 0
                let rb = Difficulty.allCases.firstIndex(of: b.slot) ?? 0
                return ra == rb ? a.textSnapshot < b.textSnapshot : ra < rb
            }
    }
    private var hiddenQuest: DailyQuest? { quests.first(where: \.isHiddenSlot) }

    private var todaysRoutines: [RoutineOccurrence] {
        // A routine swapped away is gone from the page; its replacement says what it replaced.
        occurrences.filter { $0.dueDayKey == today && !$0.isReplaced }.sorted { $0.textSnapshot < $1.textSnapshot }
    }
    private var flexibleIDs: Set<UUID> { Set(routines.filter(\.flexibleWithinWeek).map(\.id)) }
    private func isFlexible(_ o: RoutineOccurrence) -> Bool { o.routineID.map(flexibleIDs.contains) ?? false }
    // Which rows are overdue or open this week is Core's rule; these only hand it the rows the
    // queries already hold.
    private var overdueRoutines: [RoutineOccurrence] {
        Schedule.overdue(occurrences, flexible: flexibleIDs, on: today)
    }

    // Both rules live in Core; this only hands over the rows the query already has.
    private var balance: Int { Economy.balance(ledger) }
    private var totalEarned: Int { Economy.totalEarned(ledger) }
    private var level: Int { Economy.level(totalEarned: totalEarned) }
    private var freeRerollsUsed: Int { Reroll.freeRerollsUsed(ledger, on: today) }
    private var goal: SavingsGoal.Progress? {
        SavingsGoal.progress(rewards: rewards, ledger: ledger, today: today)
    }
    /// The rule itself lives in Core; this only hands it the rows the query already has.
    private var streak: Int {
        Streak.current(days: Streak.completedDayKeys(allQuests),
                       frozen: Streak.frozenDayKeys(ledger), today: today)
    }
    private var hiddenUnlocked: Bool {
        (try? DayService.hiddenUnlocked(on: today, in: context)) ?? false
    }

    // MARK: states
    // Each card renders a state Core builds from the rows the queries already hold
    // (`TodayPresentation`); nothing below chooses a number or a note.

    /// Sunday night's settlement for this week, from the rows the queries hold: each row says what
    /// it owes itself, the Ahead header adds up only its own.
    private var weeklyBill: Overdue.Weekly? {
        DayKey.weekKey(of: today).map { Overdue.weekly(routines, occurrences: occurrences, weekKey: $0) }
    }

    private func routineState(_ o: RoutineOccurrence, _ placement: RoutineRowState.Placement) -> RoutineRowState {
        RoutineRowState(o, placement: placement, routine: routines.first { $0.id == o.routineID },
                        flexible: isFlexible(o), today: today, tier: tier, level: level,
                        quests: allQuests, occurrences: occurrences,
                        sundayBill: weeklyBill?.points(for: o) ?? 0)
    }

    private func questState(_ quest: DailyQuest) -> QuestCardState { QuestCardState(quest, tier: tier) }

    private var levelState: LevelCardState {
        LevelCardState(totalEarned: totalEarned, balance: balance, streak: streak, tier: tier,
                       randomSlots: todayContext?.randomSlots ?? 0, goal: goal)
    }

    private var aheadState: AheadState {
        AheadState(routines: routines, occurrences: occurrences, flexible: flexibleIDs,
                   today: today, tier: tier) { routineState($0, $1) }
    }

    private var completedStack: CompletedStackState {
        CompletedStackState(quests: allQuests, occurrences: occurrences, today: today, tier: tier, level: level,
                            holding: settling) { routineState($0, .today) }
    }

    /// Done rows live in the Completed stack; one that has only just been completed stays put until
    /// `settle` releases it.
    private func staysInSection(_ id: UUID, isDone: Bool) -> Bool { !isDone || settling.contains(id) }

    private var cardLeaves: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96))
    }

    private var greeting: TodayGreeting {
        TodayGreeting(dayKey: today, hour: LifeCalendar.gregorian().component(.hour, from: Date()), streak: streak)
    }

    /// The page itself; the modifiers stay on `body`.
    private var questList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: LR.Spacing.sectionGap) {
                topBar
                greetingBlock
                if let generationError { BannerView(title: "Today could not be generated", message: generationError) }
                if let actionError { BannerView(message: actionError) }
                LevelCardView(state: levelState) { showingTrack = true }
                epicBlock
                routinesBlock
                questsBlock
                completedBlock
                aheadBlock
            }
            .padding(.horizontal, LR.Spacing.inset)
            .padding(.top, 8)
        }
        .background(LR.Color.canvas.ignoresSafeArea())
        .reservingTabBarSpace()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        HStack {
            Button { showingTrack = true } label: { AvatarView(size: 44) }
                .buttonStyle(PressableCardStyle())
                .accessibilityLabel("Levels")
                .accessibilityHint("Shows what each level unlocks")
            Spacer()
            Button { adding = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(LR.Color.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LR.Color.surface))
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityLabel("Add for today")
        }
    }

    private var greetingBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HandText(greeting.handLine, .hand).foregroundStyle(LR.Color.accent)
            Text(greeting.salutation).lr(.displayGreeting).foregroundStyle(LR.Color.ink)
            HandUnderlineText(lead: "let's", emphasis: "level up")
        }
        .padding(.vertical, 6)
    }

    /// The week's epic, on every day it is live — its row carries the day it was drawn, so it is
    /// looked up by `Epic.current` rather than by today's `dayKey`. Done, it stays until Sunday.
    @ViewBuilder private var epicBlock: some View {
        if let epic = currentEpic {
            let state = EpicCardState(epic, today: today, tier: tier, level: level)
            SectionTitle(title: "Epic", count: state.sectionLabel)
            if staysInSection(epic.id, isDone: state.isDone) {
                EpicCardView(state: state,
                             actions: [rerollAction(epic), extendAction(epic), replaceEpicAction(epic)].compactMap { $0 },
                             onComplete: { show(.ask(.quest(epic))) })
                    .transition(cardLeaves)
            }
        }
    }

    /// Only what is on today: due today, plus fixed routines that are overdue — those cost
    /// points every day they stay undone, so they are never folded away.
    @ViewBuilder private var routinesBlock: some View {
        if !overdueRoutines.isEmpty || !todaysRoutines.isEmpty {
            let rows = overdueRoutines.map { ($0, RoutineRowState.Placement.overdue) }
                + todaysRoutines.map { ($0, RoutineRowState.Placement.today) }
            let states = rows.map { routineState($0.0, $0.1) }
            SectionTitle(title: "Routines",
                         count: SectionProgress(done: states.filter(\.isDone).count, total: states.count).handLabel)
            ForEach(Array(rows.enumerated()), id: \.element.0.id) { index, row in
                if staysInSection(row.0.id, isDone: states[index].isDone) {
                    routineCard(row.0, states[index], menu: [cancelRoutineAction(row.0), replaceRoutineAction(row.0)])
                        .transition(cardLeaves)
                }
            }
        }
    }

    private func routineCard(_ o: RoutineOccurrence, _ state: RoutineRowState, menu: [CardAction?]) -> some View {
        RoutineRowView(state: state, actions: menu.compactMap { $0 },
                       onComplete: { show(.ask(.routine(o))) },
                       onSwitchVersion: { switchVersion(o) })
    }

    /// Today's random slots, the hidden quest once the day is cleared, and what was swapped away.
    @ViewBuilder private var questsBlock: some View {
        // Nothing drawn means nothing to clear and no hidden reward to earn — then there is no
        // lock either, rather than a lock with no key.
        let live = randomQuests.filter { !$0.replaced }
        let rows = live.filter { !$0.isTrivialGroup }
        let groups = live.filter(\.isTrivialGroup)
        let counted = live.map(questState)
        SectionTitle(title: "Today's quests",
                     count: SectionProgress(done: counted.filter(\.isDone).count, total: counted.count).handLabel)
        if randomQuests.isEmpty {
            Text("No quests today — the pool is empty or fully on cooldown. The day is yours.")
                .lr(.bodyStrong).foregroundStyle(LR.Color.inkSecondary)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .lrCard(.surface, radius: LR.Radius.row)
        }
        ForEach(rows) { quest in
            let state = questState(quest)
            if staysInSection(quest.id, isDone: state.isDone) {
                QuestRowView(state: state,
                             actions: [rerollAction(quest), cancelQuestAction(quest), replaceAction(quest)]
                                 .compactMap { $0 },
                             onComplete: { show(.ask(.quest(quest))) })
                    .transition(cardLeaves)
            }
        }
        ForEach(groups) { quest in
            let state = questState(quest)
            if staysInSection(quest.id, isDone: state.isDone) {
                MicroGroupTileView(state: state,
                                   actions: [rerollAction(quest), replaceAction(quest)].compactMap { $0 },
                                   onTick: { index in
                                       let done = quest.trivialDone.indices.contains(index) && quest.trivialDone[index]
                                       guard quest.completedAt == nil, !done else { return }
                                       show(.ask(.trivialItem(quest, index)))
                                   })
                    .transition(cardLeaves)
            }
        }
        if let hiddenQuest {
            let state = questState(hiddenQuest)
            SectionTitle(title: "Hidden", count: state.isDone ? SectionProgress.clearedLabel : nil)
            if staysInSection(hiddenQuest.id, isDone: state.isDone) {
                QuestRowView(state: state, onComplete: { show(.ask(.quest(hiddenQuest))) })
                    .transition(cardLeaves)
            }
        } else if !randomQuests.isEmpty {
            SectionTitle(title: "Hidden")
            HiddenGateTile(unlocked: hiddenUnlocked, onReveal: revealHidden)
        }
        ForEach(randomQuests.filter(\.replaced)) { ReplacedRowView(state: ReplacedRowState($0)) }
    }

    /// Everything finished today, gathered under one header after the open work.
    @ViewBuilder private var completedBlock: some View {
        let stack = completedStack
        if !stack.isEmpty {
            CompletedStackView(state: stack, expanded: $completedExpanded)
                .transition(.opacity)
        }
    }

    /// The rest of the week's flexible work, stacked like Completed: sessions from earlier days
    /// still open (full pay until Sunday), what was pulled forward today, and what can be.
    /// Saturday's session done today counts as Saturday's, and Saturday no longer carries it.
    @ViewBuilder private var aheadBlock: some View {
        let ahead = aheadState
        if !ahead.isEmpty {
            StackedCards(title: "Ahead this week", summary: ahead.summary, badge: ahead.billText,
                         accessibilityLabel: ahead.accessibilityLabel,
                         items: ahead.items, expanded: aheadBinding) { item in
                aheadRow(item)
            }
        }
    }

    /// The expand rules (`aheadOpen`) drive the stack; a toggle by hand is remembered for the day.
    private var aheadBinding: Binding<Bool> {
        Binding(get: { aheadOpen }, set: { aheadExpanded = $0; aheadToggledOn = today })
    }

    @ViewBuilder private func aheadRow(_ item: AheadItem) -> some View {
        switch item {
        case .routine(let state):
            let occurrence = occurrences.first { $0.id == state.id }
            RoutineRowView(state: state,
                           actions: occurrence.flatMap(replaceRoutineAction).map { [$0] } ?? [],
                           onComplete: { if let occurrence { show(.ask(.routine(occurrence))) } },
                           onSwitchVersion: { if let occurrence { switchVersion(occurrence) } })
        case .candidate(let state):
            AheadCandidateRowView(state: state) {
                if let routine = routines.first(where: { $0.id == state.id }) { show(.ask(.ahead(routine))) }
            }
        }
    }

    /// A routine with a light version on offer today: both versions pay the same, so switching
    /// takes no confirmation.
    private func switchVersion(_ occurrence: RoutineOccurrence) {
        do {
            try Degrade.choose(light: !occurrence.usedDegraded, for: occurrence, in: context)
            actionError = nil
        } catch {
            actionError = "\(error)"
        }
    }


    /// The page plus the one card and the level track — split off `body`, whose modifier chain is
    /// already past what the type checker handles in one expression.
    private var page: some View {
        questList
            // Behind the card the page is not reachable, for VoiceOver either.
            .accessibilityHidden(overlay != nil)
            .overlay {
                if let overlay {
                    MomentCard(header: header(for: overlay), content: content(for: overlay),
                               noticeKey: noticeKey(for: overlay))
                }
            }
            .sheet(isPresented: $showingTrack) { trackSheet }
            .onAppear { checkMoments() }
            .onChange(of: ledger.count) { checkMoments() }
            .onChange(of: overlay == nil) {
                hidesTabBar.wrappedValue = overlay != nil
                checkMoments()
            }
            .onDisappear { hidesTabBar.wrappedValue = false }
    }

    var body: some View {
        NavigationStack {
            page
            .navigationTitle("Today")
            .sheet(isPresented: $adding) {
                AdHocView(today: today, tier: tier, target: .add)
            }
            .sheet(item: $replacing) { slot in
                AdHocView(today: today, tier: tier, target: .slot(slot))
            }
            .sheet(item: $replacingRoutine) { o in
                AdHocView(today: today, tier: tier, target: .routine(o, flexible: isFlexible(o)))
            }
            .sheet(item: $replacingEpic) { epic in
                EpicReplaceView(today: today, epic: epic)
            }
        }
    }

    // MARK: the card
    // What the card shows is drawn from the same Core state the page's card uses, so the doodle and
    // tint are the card's own.

    /// Fades the card (and the dim) in and out; Reduce Motion keeps the fade and drops the movement.
    private func show(_ next: Overlay?) {
        withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.22)) { overlay = next }
    }

    private func header(for quest: DailyQuest) -> MomentHeader {
        quest.slot == .epic && !quest.isHiddenSlot
            ? MomentHeader(EpicCardState(quest, today: today, tier: tier, level: level))
            : MomentHeader(questState(quest))
    }

    private func header(for action: PendingAction) -> MomentHeader {
        switch action {
        case .quest(let quest): return header(for: quest)
        case .trivialItem(let quest, let index):
            return MomentHeader(doodle: .sparkle, tint: .trivial,
                                title: quest.trivialGroup.indices.contains(index) ? quest.trivialGroup[index] : "",
                                subtitle: "Micro-actions pay once all three are ticked")
        case .routine(let occurrence): return MomentHeader(routineState(occurrence, .today))
        case .ahead(let routine):
            let candidate = aheadState.items.lazy.compactMap { item -> AheadCandidateState? in
                if case .candidate(let state) = item, state.id == routine.id { return state }
                return nil
            }.first
            return MomentHeader(doodle: candidate?.doodle ?? DoodleKey.forText(routine.text), tint: .routine,
                                title: routine.text, subtitle: "Ahead of schedule")
        }
    }

    private func header(for spend: Spend, title: String? = nil) -> MomentHeader {
        var header: MomentHeader
        switch spend {
        case .reroll(let q), .extend(let q), .cancelQuest(let q): header = self.header(for: q)
        case .cancelRoutine(let o): header = MomentHeader(routineState(o, .today))
        }
        // The card says what is being bought and, under it, what it is bought for.
        header.subtitle = header.title
        header.title = title ?? spend.title
        return header
    }

    private func header(for overlay: Overlay) -> MomentHeader {
        switch overlay {
        case .ask(let action): header(for: action)
        case .spend(let spend): header(for: spend)
        case .refusal(let refusal): refusal.header
        case .moment(let moment): MomentHeader(doodle: .sparkle, tint: nil, title: moment.title)
        case .reveal(let roll): roll.header
        }
    }

    private func noticeKey(for overlay: Overlay) -> String {
        switch overlay {
        case .refusal: "refusal"
        default: "notice"
        }
    }

    private func content(for overlay: Overlay) -> MomentContent {
        switch overlay {
        case .ask(let action): .ask(ask(for: action))
        case .spend(let spend):
            .notice(MomentNotice(message: message(for: spend),
                                 primary: cost(of: spend) == 0 ? "Use free reroll" : "Spend \(cost(of: spend))",
                                 quiet: "Not yet",
                                 confirm: { buy(spend) },
                                 dismiss: { show(nil) }))
        case .refusal(let refusal):
            .notice(MomentNotice(message: refusal.reason, primary: "OK",
                                 confirm: { show(nil) }, dismiss: { show(nil) }))
        case .moment(let moment):
            .notice(MomentNotice(message: moment.message, primary: "Nice",
                                 confirm: { dismiss(moment) }, dismiss: { dismiss(moment) }))
        case .reveal(let roll):
            .payout(MomentPayout(id: roll.id, amount: roll.amount) { value in
                if let value { record(rating: value, for: roll) }
                show(nil)
            })
        }
    }

    /// What a pick pays, as the pill on its button: the same Core rule `completeAhead` applies.
    private func aheadPill(_ basePoints: [Int]) -> String {
        let points = basePoints.map { Scoring.routinePoints(basePoints: $0, tier: tier, late: false) }
        return "+" + PresentationText.range((points.min() ?? 0)...(points.max() ?? 0))
    }

    private func ask(for action: PendingAction) -> MomentAsk {
        // Done ahead there is no row to switch versions on afterwards, so on a low day the version
        // is picked here, and a lighter version pays its own points.
        if case .ahead(let routine) = action, offersLightVersion(routine) {
            return MomentAsk(
                lead: .fixed(pill: nil),
                choices: [
                    .init(title: "Did the original", pill: aheadPill([routine.basePoints])) {
                        perform(action, light: false)
                    },
                    .init(title: "Did a lighter version",
                          pill: aheadPill(Degrade.versions(of: routine, in: routines).map(\.basePoints)),
                          outlined: true) {
                        perform(action, light: true)
                    },
                ],
                footnote: "Lighter: \(lightVersionList(routine))",
                notYet: { show(nil) })
        }
        return MomentAsk(lead: payoutLead(for: action),
                         choices: [.init(title: "Complete") { perform(action) }], notYet: { show(nil) })
    }

    /// A routine pays a fixed number, known before it is tapped, so its card has no reel: the
    /// number is a pill under the title. A quest's is rolled at completion and keeps the reel.
    private func payoutLead(for action: PendingAction) -> MomentAsk.Lead {
        switch action {
        case .quest, .trivialItem: .reel
        case .routine(let occurrence):
            .fixed(pill: routineState(occurrence, .today).pills.first { $0.kind == .payout }?.text)
        case .ahead(let routine): .fixed(pill: aheadPill([routine.basePoints]))
        }
    }

    /// The whole level track, unlocked and still ahead (`Perks.track`).
    private var trackSheet: some View {
        NavigationStack {
            List {
                Section {
                    Text("Lv \(level) · \(totalEarned) earned · \(Economy.pointsToNextLevel(totalEarned: totalEarned)) to the next level")
                        .font(.subheadline)
                }
                Section("Perks") {
                    ForEach(Perks.track, id: \.self) { perk in
                        let open = Perks.has(perk, at: level)
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: open ? "checkmark.circle.fill" : "lock")
                                .foregroundStyle(open ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(perk.summary)
                                Text("Lv \(perk.level) · \(Economy.earnedNeeded(forLevel: perk.level)) earned")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(open ? .primary : .secondary)
                    }
                }
            }
            .navigationTitle("Levels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showingTrack = false } }
            }
        }
    }

    // MARK: level-ups and streak milestones

    /// Whatever hasn't been announced yet, as one card: a level reached since the last one shown
    /// and streak bonuses booked since then. Held back while any other card is up, so the two
    /// don't stack — the card going down calls this again.
    private func checkMoments() {
        guard overlay == nil else { return }
        let from = max(1, announcedLevel)
        let bonuses = ledger
            .filter { $0.kind == Economy.Kind.streak.rawValue
                      && $0.timestamp.timeIntervalSince1970 > announcedStreakBonusAt }
            .sorted { $0.timestamp < $1.timestamp }
        let levelUp = level > from
        guard levelUp || !bonuses.isEmpty else {
            if announcedLevel == 0 { announcedLevel = level }         // nothing to say yet
            return
        }
        var titles: [String] = []
        var lines: [String] = []
        for b in bonuses {
            let days = StreakMilestone.threshold(of: b).map { "\($0) days in a row" } ?? "Streak bonus"
            titles.append(days)
            lines.append("\(days) · +\(b.points)")
        }
        if levelUp {
            titles.append("Level \(level)")
            let perks = Perks.newlyUnlocked(from: from, to: level)
            lines.append(perks.isEmpty ? "Reached level \(level)."
                                       : "Unlocked:\n" + perks.map { "· \($0.summary)" }.joined(separator: "\n"))
        }
        show(.moment(Moment(title: titles.joined(separator: " · "),
                            message: lines.joined(separator: "\n\n"),
                            level: level,
                            streakBonusAt: bonuses.last.map { $0.timestamp.timeIntervalSince1970 }
                                ?? announcedStreakBonusAt)))
    }

    /// However the card is closed (its pill, the dim, VoiceOver's escape), it was announced once.
    private func dismiss(_ moment: Moment) {
        announcedLevel = moment.level
        announcedStreakBonusAt = moment.streakBonusAt
        show(nil)
    }

    // MARK: actions

    /// The confirmation was the only step: this writes the completion, and the card then turns into
    /// the payout where it stands (`reveal`), or goes down when there is nothing to roll.
    private func perform(_ action: PendingAction, light: Bool = true) {
        var rng = SystemRandomNumberGenerator()
        var next: Overlay?
        // Read before the completion: an ahead candidate is gone from the page once it is done.
        let header = header(for: action)
        do {
            switch action {
            case .quest(let quest):
                let points = try Completion.complete(quest, tier: tier, in: context, rng: &rng)
                next = reveal(points, for: quest)
                settle(quest.id)
            case .trivialItem(let quest, let index):
                // Nil until the third tick: the group scores once, as a whole.
                if let points = try Completion.tickTrivialItem(quest, at: index, tier: tier,
                                                               in: context, rng: &rng) {
                    next = reveal(points, for: quest)
                    settle(quest.id)
                }
            case .routine(let occurrence):
                // A fixed payout, nothing rolled: the card shows the number it paid and asks how it felt.
                let points = try Completion.completeRoutine(occurrence, on: today, tier: tier, in: context)
                next = reveal(points, forRoutine: occurrence, header: header)
                settle(occurrence.id)
            case .ahead(let routine):
                let points = try Completion.completeAhead(routine, on: today, tier: tier, light: light, in: context)
                next = reveal(points, aheadOf: routine, header: header)
            }
            // The tap that opened the confirmation is silent; this is the completion itself.
            Haptics.impact(.medium)
            actionError = nil
        } catch {
            actionError = "\(error)"
        }
        show(next)
    }

    /// Lets a just-completed card finish its own completion before it moves into the stack.
    private func settle(_ id: UUID) {
        settling.insert(id)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.3)) {
                _ = settling.remove(id)
            }
        }
    }

    /// Describes what was already paid. The roll happened inside `Completion.complete` and is on
    /// disk by the time this runs — `Scoring.breakdown` only describes it, and the card never
    /// decides the number it shows.
    private func reveal(_ points: Int, for quest: DailyQuest) -> Overlay {
        .reveal(Roll(header: header(for: quest),
                     amount: .rolled(Scoring.breakdown(quest, tier: tier, awarded: points)),
                     target: .quest,
                     questID: quest.id,
                     templateID: quest.templateID,
                     text: quest.textSnapshot,
                     // The epic lives all week; it was done (and rated) today, not on Monday.
                     dayKey: quest.slot == .epic ? today : quest.dayKey))
    }

    private func reveal(_ points: Int, forRoutine occurrence: RoutineOccurrence, header: MomentHeader) -> Overlay {
        .reveal(Roll(header: header, amount: .fixed(points), target: .routine,
                     questID: occurrence.id, templateID: occurrence.routineID,
                     text: occurrence.displayText, dayKey: today))
    }

    /// Doing a routine ahead creates its occurrence inside `Completion.completeAhead`; the rating
    /// is linked to it (so the day detail shows it on the routine) when it can be found again.
    private func reveal(_ points: Int, aheadOf routine: RoutineTask, header: MomentHeader) -> Overlay {
        let id: UUID? = routine.id
        var found = FetchDescriptor<RoutineOccurrence>(
            predicate: #Predicate { $0.routineID == id && $0.awardedPoints != nil },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)])
        found.fetchLimit = 1
        let occurrence = try? context.fetch(found).first
        return .reveal(Roll(header: header, amount: .fixed(points), target: .routine,
                            questID: occurrence?.id, templateID: routine.id,
                            text: occurrence?.displayText ?? routine.text, dayKey: today))
    }

    /// Rating is never required, so a failure here must not interrupt anything — the points are
    /// already banked and the quest is already done.
    private func record(rating: Int, for roll: Roll) {
        Feedback.rate(context, target: roll.target, id: roll.templateID, questID: roll.questID,
                      text: roll.text, rating: rating, dayKey: roll.dayKey)
        try? Affinity.sync(context)           // the next draw already weighs it
        try? context.save()
    }
    // The `⋯` menu, the context menu and VoiceOver's custom actions all list these. Whether each
    // can go through is Core's rule; when it can't, the item is greyed out. The popover keeps its
    // price pill, the context menu and VoiceOver title drop the price.

    private func rerollAction(_ quest: DailyQuest) -> CardAction? {
        guard quest.completedAt == nil else { return nil }
        return spendAction(.reroll(quest), "Reroll", "dice",
                           open: Reroll.blocked(for: quest, on: today, balance: balance, level: level,
                                                freeUsedToday: freeRerollsUsed) == nil)
    }

    private func extendAction(_ epic: DailyQuest) -> CardAction? {
        guard epic.completedAt == nil else { return nil }
        return spendAction(.extend(epic), "Extend", "calendar.badge.plus",
                           open: Epic.blocked(epic, on: today, balance: balance, level: level) == nil)
    }

    /// Free — the price of an ad-hoc routine is that it now loses points if left undone — so it
    /// only appears where it applies rather than sitting greyed out on every card.
    private func replaceAction(_ quest: DailyQuest) -> CardAction? {
        replaceableIDs.contains(quest.id)
            ? CardAction(title: "Replace", systemImage: "arrow.triangle.swap") { replacing = quest } : nil
    }

    /// Free, for something at least as heavy (`AdHoc.replaceRoutine`); only where it applies.
    private func replaceRoutineAction(_ o: RoutineOccurrence) -> CardAction? {
        AdHoc.isReplaceable(o, flexible: isFlexible(o), on: today)
            ? CardAction(title: "Replace", systemImage: "arrow.triangle.swap") { replacingRoutine = o } : nil
    }

    /// Free (`Epic.replace`); gone once the epic is done or extended.
    private func replaceEpicAction(_ epic: DailyQuest) -> CardAction? {
        Epic.blockedReplace(epic, on: today) == nil
            ? CardAction(title: "Replace", systemImage: "arrow.triangle.swap") { replacingEpic = epic } : nil
    }

    private func cancelQuestAction(_ quest: DailyQuest) -> CardAction? {
        guard quest.completedAt == nil, Redemption.cancelCost(for: quest.slot) != nil else { return nil }
        return spendAction(.cancelQuest(quest), "Cancel", "xmark",
                           open: Redemption.blocked(cancelling: quest, on: today, balance: balance) == nil)
    }

    /// Only the routines a cancel can apply to get the item at all — a flexible one or a
    /// check-in never could, so a permanently grey item there would just be noise.
    private func cancelRoutineAction(_ o: RoutineOccurrence) -> CardAction? {
        let blocked = Redemption.blocked(cancelling: o, flexible: isFlexible(o), on: today, balance: balance)
        guard blocked != .notAvailable, blocked != .alreadyCompleted else { return nil }
        return spendAction(.cancelRoutine(o), "Cancel", "xmark", open: blocked == nil)
    }

    private func spendAction(_ spend: Spend, _ name: String, _ icon: String, open: Bool) -> CardAction {
        CardAction(title: open ? "\(name) · \(cost(of: spend) == 0 ? "free" : "\(cost(of: spend))")" : name,
                   systemImage: icon, isEnabled: open, label: name, trailing: price(spend)) { show(.spend(spend)) }
    }


    private func message(for spend: Spend) -> String {
        switch spend {
        case .reroll(let q):
            q.slot == .epic
                ? "Swap it for a different epic for \(price(spend)). It keeps the same deadline. Once extended, an epic can't be rerolled."
                : "Swap it for a different \(q.slot.code) for \(price(spend)). The next reroll of this slot today costs more."
        case .extend:
            "One more week, for \(price(spend)). The week it runs into gets no new epic, and it can't be rerolled or replaced any more."
        case .cancelQuest:
            "Drop it for \(price(spend)). It no longer blocks the hidden quest, but it earns nothing and doesn't count toward the streak."
        case .cancelRoutine:
            "Drop it for \(price(spend)). No more overdue deductions, and it no longer blocks the hidden quest. Deductions already charged stay."
        }
    }

    private func buy(_ spend: Spend) {
        var rng = SystemRandomNumberGenerator()
        do {
            switch spend {
            case .reroll(let q): try Reroll.perform(q, on: today, in: context, rng: &rng)
            case .extend(let q): try Epic.extend(q, on: today, in: context)
            case .cancelQuest(let q): try Redemption.cancel(q, on: today, in: context)
            case .cancelRoutine(let o):
                try Redemption.cancel(o, flexible: isFlexible(o), on: today, in: context)
            }
            actionError = nil
        } catch let refused as Purchase.Blocked {
            // Only a reroll can be refused this late (nothing left to draw); nothing was charged.
            if case .reroll = spend {
                show(.refusal(RerollRefusal(header: header(for: spend, title: "Can't reroll"),
                                            reason: "\(refused.description). Nothing was charged.")))
                return
            }
            actionError = refused.description
        } catch {
            actionError = "\(error)"
        }
        show(nil)
    }

    private func revealHidden() {
        var rng = SystemRandomNumberGenerator()
        do {
            if try DayService.drawHidden(context, on: today, inputs: inputs, rng: &rng) == nil {
                actionError = "No hidden quest available — the pool is empty or on cooldown."
            } else {
                actionError = nil
            }
        } catch {
            actionError = "\(error)"
        }
    }
}

#Preview {
    TodayView(today: Date().dayKey, generationError: nil)
        .modelContainer(for: LifeRPGSchema.models, inMemory: true)
}
