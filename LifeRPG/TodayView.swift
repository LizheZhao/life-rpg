import LifeRPGCore
import SwiftData
import SwiftUI

/// The daily page: level card, epic, routines (overdue pinned on top), today's random slots, and
/// the hidden quest once the day is cleared.
///
/// There is no undo anywhere on this page — completion writes a ledger entry and starts the
/// template's cooldown, both final. That is why every tap goes through a confirmation.
struct TodayView: View {
    let today: String
    let generationError: String?

    @Environment(\.modelContext) private var context

    // Small tables (a handful of rows per day), so the whole set is queried and filtered here
    // rather than rebuilding a predicate every time the day rolls over.
    @Query(sort: \DailyQuest.dayKey) private var allQuests: [DailyQuest]
    @Query private var ledger: [LedgerEntry]
    @Query private var contexts: [DailyContext]
    @Query private var occurrences: [RoutineOccurrence]
    @Query private var routines: [RoutineTask]
    @Query private var rewards: [Reward]

    @State private var pending: PendingAction?
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
    @State private var roll: Roll?
    @State private var actionError: String?
    /// A purchase waiting for its confirmation. Spending is as final as completing, so it asks too.
    @State private var spending: Spend?
    /// A reroll that was refused only once it tried to draw (nothing else in the pool).
    @State private var rerollRefusal: String?
    /// A level-up or streak milestone waiting to be shown, once the payout reveal is out of the way.
    @State private var moment: Moment?
    @State private var showingTrack = false
    /// What has already been announced. A UI convenience, not data: losing it only shows a card
    /// once more. 0 = never announced, which on the first launch after an update lists the perks
    /// already unlocked.
    @AppStorage("announcedLevel") private var announcedLevel = 0
    @AppStorage("announcedStreakBonusAt") private var announcedStreakBonusAt: Double = 0

    private struct Moment: Identifiable {
        let id = UUID()
        var title: String
        var message: String
        var level: Int
        var streakBonusAt: Double
    }

    /// A payout that has already happened and is already in the ledger, waiting to be shown.
    private struct Roll: Identifiable {
        let id = UUID()
        var title: String
        var slotLabel: String
        var breakdown: Scoring.Breakdown
        /// Carried so the rating can be filed against the exact completion that prompted it,
        /// not just against the template.
        var questID: UUID
        var templateID: UUID?
        var text: String
        var dayKey: String
    }

    /// Everything bought from a row's swipe actions. The rules and prices are Core's; this only
    /// says what the confirmation reads.
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

        var label: String {
            switch self {
            case .quest(let q): [q.textSnapshot, q.variantSnapshot]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
            case .trivialItem(let q, let i): q.trivialGroup.indices.contains(i) ? q.trivialGroup[i] : ""
            case .routine(let o): o.displayText
            case .ahead(let r): "\(r.text) (ahead of schedule)"
            }
        }
    }

    private var todayContext: DailyContext? { contexts.first { $0.dayKey == today } }
    private var tier: Tier { todayContext?.tier ?? .normal }
    private var cycleDay: Int? { todayContext?.cycleDay }
    /// The day's measured state, as stored. Both completion scoring and the hidden draw read this
    /// same value — a hidden quest drawn under `normal` rules on a very-low day would hand out the
    /// hardest thing in the pool as the reward for a day you barely got through.
    private var inputs: DayInputs { DayInputs(tier: tier, cycleDay: cycleDay) }

    /// What doing this routine ahead would pay. On a low day one of its downgrade versions is
    /// drawn when it is done, so what is shown is the range across the versions on offer rather
    /// than a number the draw could contradict.
    private func aheadPayout(_ routine: RoutineTask) -> ClosedRange<Int> {
        let bases = [routine.basePoints] + Degrade.versions(of: routine, in: routines).map(\.basePoints)
        let candidates = tier.isLow && routine.canDegrade ? Array(bases.dropFirst()) : [routine.basePoints]
        let points = candidates.map { Scoring.routinePoints(basePoints: $0, tier: tier, late: false) }
        return (points.min() ?? 0)...(points.max() ?? 0)
    }

    private var aheadPending: Int { thisWeekRoutines.count + aheadCandidates.count }

    private var aheadOpen: Bool {
        aheadToggledOn == today ? aheadExpanded : (DayKey.isWeekend(today) || aheadExpanded)
    }

    /// What Sunday night's flexible settlement would charge if nothing more is done — the same
    /// rule that will charge it (`Overdue.weekly`), from the rows the queries already hold.
    private var weekEndBill: Int {
        guard let week = DayKey.weekKey(of: today) else { return 0 }
        return Overdue.weekly(routines, occurrences: occurrences, weekKey: week).total
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
    // Which rows are overdue, open this week or in the backlog is Core's rule; these only hand
    // it the rows the queries already hold.
    private var overdueRoutines: [RoutineOccurrence] {
        Schedule.overdue(occurrences, flexible: flexibleIDs, on: today)
    }
    private var thisWeekRoutines: [RoutineOccurrence] {
        Schedule.openThisWeek(occurrences, flexible: flexibleIDs, on: today)
    }
    private var backlog: [RoutineOccurrence] { Array(Schedule.backlog(occurrences).prefix(30)) }
    private var aheadCandidates: [Schedule.Ahead] {
        Schedule.aheadCandidates(routines, occurrences: occurrences, on: today)
    }
    private var doneAhead: [RoutineOccurrence] { Schedule.doneAhead(occurrences, on: today) }

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

    private func routineState(_ o: RoutineOccurrence, _ placement: RoutineRowState.Placement) -> RoutineRowState {
        RoutineRowState(o, placement: placement, routine: routines.first { $0.id == o.routineID },
                        flexible: isFlexible(o), today: today, tier: tier, level: level,
                        quests: allQuests, occurrences: occurrences)
    }

    private func questState(_ quest: DailyQuest) -> QuestCardState { QuestCardState(quest, tier: tier) }

    private var levelState: LevelCardState {
        LevelCardState(totalEarned: totalEarned, balance: balance, streak: streak, tier: tier,
                       randomSlots: todayContext?.randomSlots ?? 0, goal: goal)
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
                aheadBlock
                backlogBlock
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
            Text(greeting.handLine).lr(.hand).foregroundStyle(LR.Color.inkHand)
            Text(greeting.salutation).lr(.displayGreeting).foregroundStyle(LR.Color.ink)
            HandUnderlineText(lead: "let's", emphasis: "level up")
        }
        .padding(.vertical, 6)
    }

    /// The week's epic, on every day it is live — its row carries the day it was drawn, so it is
    /// looked up by `Epic.current` rather than by today's `dayKey`. Done, it stays until Sunday.
    @ViewBuilder private var epicBlock: some View {
        if let epic = currentEpic {
            SectionTitle(title: "Epic", count: "this week")
            EpicCardView(state: EpicCardState(epic, today: today, tier: tier, level: level),
                         actions: [rerollAction(epic), extendAction(epic), replaceEpicAction(epic)].compactMap { $0 },
                         onComplete: { pending = .quest(epic) })
        }
    }

    /// Only what is on today: due today, plus fixed routines that are overdue — those cost
    /// points every day they stay undone, so they are never folded away.
    @ViewBuilder private var routinesBlock: some View {
        if !overdueRoutines.isEmpty || !todaysRoutines.isEmpty {
            let rows = overdueRoutines.map { ($0, RoutineRowState.Placement.overdue) }
                + todaysRoutines.map { ($0, RoutineRowState.Placement.today) }
            let states = rows.map { routineState($0.0, $0.1) }
            SectionTitle(title: "Routines", count: "\(states.filter(\.isDone).count) / \(states.count) done")
            ForEach(Array(rows.enumerated()), id: \.element.0.id) { index, row in
                routineCard(row.0, states[index], menu: [cancelRoutineAction(row.0), replaceRoutineAction(row.0)])
            }
        }
    }

    private func routineCard(_ o: RoutineOccurrence, _ state: RoutineRowState, menu: [CardAction?]) -> some View {
        RoutineRowView(state: state, actions: menu.compactMap { $0 },
                       onComplete: { pending = .routine(o) },
                       onSwitchVersion: { switchVersion(o) })
    }

    /// Today's random slots, the hidden quest once the day is cleared, and what was swapped away.
    @ViewBuilder private var questsBlock: some View {
        // Nothing drawn means nothing to clear and no hidden reward to earn — then there is no
        // lock either, rather than a lock with no key.
        let live = randomQuests.filter { !$0.replaced }
        let tiles = live.filter { !$0.isTrivialGroup }
        let groups = live.filter(\.isTrivialGroup)
        let counted = live.map(questState)
        SectionTitle(title: "Today's quests",
                     count: counted.isEmpty ? nil : "\(counted.filter(\.isDone).count) / \(counted.count) done")
        if randomQuests.isEmpty {
            Text("No quests today — the pool is empty or fully on cooldown. The day is yours.")
                .lr(.bodyStrong).foregroundStyle(LR.Color.inkSecondary)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .lrCard(.surface, radius: LR.Radius.row)
        }
        if !tiles.isEmpty {
            TileGrid {
                ForEach(tiles) { quest in
                    QuestTileView(state: questState(quest),
                                  actions: [rerollAction(quest), cancelQuestAction(quest), replaceAction(quest)]
                                      .compactMap { $0 },
                                  onComplete: { pending = .quest(quest) })
                }
            }
        }
        ForEach(groups) { quest in
            MicroGroupTileView(state: questState(quest),
                               actions: [rerollAction(quest), replaceAction(quest)].compactMap { $0 },
                               onTick: { index in
                                   let done = quest.trivialDone.indices.contains(index) && quest.trivialDone[index]
                                   guard quest.completedAt == nil, !done else { return }
                                   pending = .trivialItem(quest, index)
                               })
        }
        if let hiddenQuest {
            SectionTitle(title: "Hidden")
            QuestTileView(state: questState(hiddenQuest), onComplete: { pending = .quest(hiddenQuest) })
        } else if !randomQuests.isEmpty {
            SectionTitle(title: "Hidden")
            HiddenGateTile(unlocked: hiddenUnlocked, onReveal: revealHidden)
        }
        ForEach(randomQuests.filter(\.replaced)) { ReplacedRowView(state: ReplacedRowState($0)) }
    }

    /// The rest of the week's flexible work, folded away: sessions from earlier days still open
    /// (full pay until Sunday), what was pulled forward today, and what can be.
    /// Saturday's session done today counts as Saturday's, and Saturday no longer carries it.
    @ViewBuilder private var aheadBlock: some View {
        if !thisWeekRoutines.isEmpty || !aheadCandidates.isEmpty || !doneAhead.isEmpty {
            aheadHeader
            if aheadOpen {
                ForEach(thisWeekRoutines) { o in
                    routineCard(o, routineState(o, .thisWeek), menu: [replaceRoutineAction(o)])
                }
                ForEach(doneAhead) { o in
                    RecordRowView(title: o.displayText, caption: "Done ahead · counts for \(o.dueDayKey)",
                                  doodle: DoodleKey.forText(o.displayText)) {
                        PillLabel(text: "+\(o.awardedPoints ?? 0)")
                    }
                }
                ForEach(aheadCandidates, id: \.routine.id) { c in
                    RecordRowView(title: c.routine.text,
                                  caption: "\(c.doneThisWeek)/\(c.routine.weeklyTarget) this week · next due \(c.nextDueDayKey)",
                                  doodle: DoodleKey.forText(c.routine.text)) {
                        VStack(alignment: .trailing, spacing: 6) {
                            PillLabel(text: PresentationText.range(aheadPayout(c.routine)))
                            Button("Do now") { pending = .ahead(c.routine) }
                                .buttonStyle(DoNowButtonStyle())
                        }
                    }
                }
            }
        }
    }

    private var aheadHeader: some View {
        Button {
            let open = !aheadOpen
            withAnimation {
                aheadExpanded = open
                aheadToggledOn = today
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Ahead this week").lr(.heading).foregroundStyle(LR.Color.ink)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(LR.Color.inkSecondary)
                        .rotationEffect(.degrees(aheadOpen ? 90 : 0))
                }
                FlowRow(spacing: 6) {
                    PillLabel(text: "\(aheadPending) open")
                    if !doneAhead.isEmpty { PillLabel(text: "\(doneAhead.count) done") }
                    if weekEndBill > 0 { PillLabel(text: "−\(weekEndBill) Sun night", style: .clay) }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .lrCard(.surface, radius: LR.Radius.row)
            .contentShape(RoundedRectangle(cornerRadius: LR.Radius.row, style: .continuous))
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ahead this week, \(aheadPending) open"
                            + (doneAhead.isEmpty ? "" : ", \(doneAhead.count) done")
                            + (weekEndBill > 0 ? ", minus \(weekEndBill) coins Sunday night" : ""))
        .accessibilityValue(aheadOpen ? "expanded" : "collapsed")
        .accessibilityAddTraits(.isButton)
    }

    /// Skipped and never done: read-only, a record rather than a to-do.
    @ViewBuilder private var backlogBlock: some View {
        if !backlog.isEmpty {
            SectionTitle(title: "Backlog")
            ForEach(backlog) { o in
                RecordRowView(title: o.textSnapshot, caption: "Due \(o.dueDayKey)", secondary: true) {
                    if o.penaltyApplied > 0 {
                        PillLabel(text: "−\(o.penaltyApplied)", style: .clay)
                    }
                }
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


    /// The page plus the level-up / milestone card and the level track — split off `body`, whose
    /// modifier chain is already past what the type checker handles in one expression.
    private var page: some View {
        questList
            .alert(moment?.title ?? "",
                   isPresented: Binding(get: { moment != nil }, set: { if !$0 { moment = nil } }),
                   presenting: moment) { m in
                Button("Nice") {
                    announcedLevel = m.level
                    announcedStreakBonusAt = m.streakBonusAt
                }
            } message: { m in
                Text(m.message)
            }
            .sheet(isPresented: $showingTrack) { trackSheet }
            .onAppear { checkMoments() }
            .onChange(of: ledger.count) { checkMoments() }
            .onChange(of: roll == nil) { checkMoments() }
    }

    var body: some View {
        NavigationStack {
            page
            .navigationTitle("Today")
            // An alert rather than a sheet or an inline toggle: completion is irreversible, so it
            // asks once, every time. The action arrives through `presenting:` rather than being
            // read back out of `pending` inside the button. SwiftUI does run the action before the
            // dismissal clears that state — measured, not assumed — but the ordering isn't
            // documented, and the failure it would cause is a tap that silently completes nothing.
            .alert("Mark as done?",
                   isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                   presenting: pending) { action in
                // Done ahead there is no row to switch versions on afterwards, so on a low day the
                // version is picked here — and a lighter version pays its own points.
                if case .ahead(let routine) = action, offersLightVersion(routine) {
                    Button("Did a lighter version") { perform(action, light: true) }
                    Button("Did the original") { perform(action, light: false) }
                } else {
                    Button("Complete") { perform(action) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { action in
                if case .ahead(let routine) = action, offersLightVersion(routine) {
                    Text("\(routine.text)\nLighter: \(lightVersionList(routine))\n\nA lighter version pays its own points, and one of them is drawn when you pick it. This is final — completion cannot be undone.")
                } else {
                    Text("\(action.label)\n\nThis is final — completion cannot be undone.")
                }
            }
            // Only reachable when the purchase can go through: its swipe button is greyed out otherwise.
            .alert(spending?.title ?? "",
                   isPresented: Binding(get: { spending != nil },
                                        set: { if !$0 { spending = nil } }),
                   presenting: spending) { spend in
                Button(cost(of: spend) == 0 ? "Use free reroll" : "Spend \(cost(of: spend))") { buy(spend) }
                Button("Keep it", role: .cancel) {}
            } message: { spend in
                Text(message(for: spend))
            }
            .alert("Can't reroll",
                   isPresented: Binding(get: { rerollRefusal != nil },
                                        set: { if !$0 { rerollRefusal = nil } }),
                   presenting: rerollRefusal) { _ in
                Button("OK", role: .cancel) {}
            } message: { reason in
                Text(reason)
            }
            .overlay {
                if let roll {
                    PointsRollView(title: roll.title, slotLabel: roll.slotLabel,
                                   breakdown: roll.breakdown) { value in
                        if let value { record(rating: value, for: roll) }
                        withAnimation(.easeOut(duration: 0.18)) { self.roll = nil }
                    }
                    .transition(.opacity)
                }
            }
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
    /// and streak bonuses booked since then. Held back while the payout reveal is up, so the two
    /// don't stack — the reveal's dismissal calls this again.
    private func checkMoments() {
        guard roll == nil, moment == nil else { return }
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
        moment = Moment(title: titles.joined(separator: " · "),
                        message: lines.joined(separator: "\n\n"),
                        level: level,
                        streakBonusAt: bonuses.last.map { $0.timestamp.timeIntervalSince1970 } ?? announcedStreakBonusAt)
    }

    // MARK: actions

    private func perform(_ action: PendingAction, light: Bool = true) {
        var rng = SystemRandomNumberGenerator()
        do {
            switch action {
            case .quest(let quest):
                let points = try Completion.complete(quest, tier: tier, in: context, rng: &rng)
                reveal(points, for: quest)
            case .trivialItem(let quest, let index):
                // Nil until the third tick: the group scores once, as a whole.
                if let points = try Completion.tickTrivialItem(quest, at: index, tier: tier,
                                                               in: context, rng: &rng) {
                    reveal(points, for: quest)
                }
            case .routine(let occurrence):
                // A fixed payout, nothing rolled — the number lands on the row, no reveal.
                try Completion.completeRoutine(occurrence, on: today, tier: tier, in: context)
            case .ahead(let routine):
                try Completion.completeAhead(routine, on: today, tier: tier, light: light, in: context)
            }
            // The tap that opened the confirmation is silent; this is the completion itself.
            Haptics.impact(.medium)
            actionError = nil
        } catch {
            actionError = "\(error)"
        }
        pending = nil
    }

    /// Shows what was already paid. The roll happened inside `Completion.complete` and is on disk
    /// by the time this runs — `Scoring.breakdown` only describes it.
    private func reveal(_ points: Int, for quest: DailyQuest) {
        withAnimation(.easeOut(duration: 0.2)) {
            roll = Roll(title: quest.isTrivialGroup ? quest.trivialGroup.joined(separator: " · ")
                                                    : quest.textSnapshot,
                        slotLabel: quest.isTrivialGroup ? "T×3"
                                 : quest.isHiddenSlot ? "★" : quest.slot.code,
                        breakdown: Scoring.breakdown(quest, tier: tier, awarded: points),
                        questID: quest.id,
                        templateID: quest.templateID,
                        text: quest.textSnapshot,
                        // The epic lives all week; it was done (and rated) today, not on Monday.
                        dayKey: quest.slot == .epic ? today : quest.dayKey)
        }
    }

    /// Rating is never required, so a failure here must not interrupt anything — the points are
    /// already banked and the quest is already done.
    private func record(rating: Int, for roll: Roll) {
        Feedback.rate(context, target: .quest, id: roll.templateID, questID: roll.questID,
                      text: roll.text, rating: rating, dayKey: roll.dayKey)
        try? Affinity.sync(context)           // the next draw already weighs it
        try? context.save()
    }
    // The `⋯` menu, the context menu and VoiceOver's custom actions all list these. Whether each
    // can go through is Core's rule; when it can't, the item is greyed out and shows no price.

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
                   systemImage: icon, isEnabled: open) { spending = spend }
    }


    private func slotText(_ quest: DailyQuest) -> String {
        quest.isTrivialGroup ? quest.trivialGroup.joined(separator: " · ") : quest.textSnapshot
    }

    private func message(for spend: Spend) -> String {
        switch spend {
        case .reroll(let q):
            "\(slotText(q))\n\n" + (q.slot == .epic
                ? "Swap it for a different epic for \(price(spend)). It keeps the same deadline. Once extended, an epic can't be rerolled."
                : "Swap it for a different \(q.slot.code) for \(price(spend)). The next reroll of this slot today costs more.")
        case .extend(let q):
            "\(q.textSnapshot)\n\nOne more week, for \(price(spend)). The week it runs into gets no new epic, and it can't be rerolled or replaced any more."
        case .cancelQuest(let q):
            "\(slotText(q))\n\nDrop it for \(price(spend)). It no longer blocks the hidden quest, but it earns nothing and doesn't count toward the streak."
        case .cancelRoutine(let o):
            "\(o.displayText)\n\nDrop it for \(price(spend)). No more overdue deductions, and it no longer blocks the hidden quest. Deductions already charged stay."
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
            if case .reroll(let q) = spend {
                rerollRefusal = "\(slotText(q))\n\n\(refused.description). Nothing was charged."
            } else {
                actionError = refused.description
            }
        } catch {
            actionError = "\(error)"
        }
        spending = nil
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

/// "Do now": a filled capsule with a 44 pt target.
private struct DoNowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lr(.bodyStrong)
            .foregroundStyle(LR.Color.onFill)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Capsule().fill(LR.Color.fill))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

#Preview {
    TodayView(today: Date().dayKey, generationError: nil)
        .modelContainer(for: LifeRPGSchema.models, inMemory: true)
}
