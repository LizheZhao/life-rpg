import LifeRPGCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The daily page: HUD, routines (overdue pinned on top), today's random slots, and the hidden
/// quest once the day is cleared.
///
/// There is no undo anywhere on this page — completion writes a ledger entry and starts the
/// template's cooldown, both final. That is why every tap goes through a confirmation.
struct TodayView: View {
    let today: String
    let generationError: String?
    /// Re-runs the day after an import, so a backup that ends before today catches up at once
    /// instead of on the next foreground.
    var onImported: () -> Void = {}

    @Environment(\.modelContext) private var context

    // Small tables (a handful of rows per day), so the whole set is queried and filtered here
    // rather than rebuilding a predicate every time the day rolls over.
    @Query(sort: \DailyQuest.dayKey) private var allQuests: [DailyQuest]
    @Query private var ledger: [LedgerEntry]
    @Query private var contexts: [DailyContext]
    @Query private var occurrences: [RoutineOccurrence]
    @Query private var routines: [RoutineTask]

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
    /// One export at a time, through one `fileExporter` — the JSON dump and the CSV folder are
    /// the same kind of thing to the save dialog, so they don't need a presentation each.
    @State private var pendingExport: ExportDocument?
    @State private var exporting = false
    @State private var importing = false
    /// A decoded backup waiting for the overwrite to be confirmed. Nothing is written until then.
    @State private var importPlan: JSONImport.Plan?
    /// A purchase waiting for its confirmation. Spending is as final as completing, so it asks too.
    @State private var spending: Spend?
    /// A reroll that was refused only once it tried to draw (nothing else in the pool).
    @State private var rerollRefusal: String?

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

        var cost: Int {
            switch self {
            case .reroll(let q): Reroll.cost(for: q)
            case .extend: Epic.extensionCost
            case .cancelQuest(let q): Redemption.cancelCost(for: q.slot) ?? 0
            case .cancelRoutine: Redemption.cancelRoutineCost
            }
        }
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

    /// Only what is on today: due today, plus fixed routines that are overdue — those cost
    /// points every day they stay undone, so they are never folded away.
    @ViewBuilder private var routinesSection: some View {
        // Only what is on today: due today, plus fixed routines that are overdue — those
        // cost points every day they stay undone, so they are never folded away.
        if !overdueRoutines.isEmpty || !todaysRoutines.isEmpty {
            Section("Routines") {
                ForEach(overdueRoutines) { o in
                    routineRow(o, note: .overdue).swipeActions(edge: .trailing) {
                        cancelRoutineButton(o)
                        replaceRoutineButton(o)
                    }
                }
                ForEach(todaysRoutines) { o in
                    routineRow(o).swipeActions(edge: .trailing) {
                        cancelRoutineButton(o)
                        replaceRoutineButton(o)
                    }
                }
            }
        }
    }

    /// The week's epic, on every day it is live — its row carries the day it was drawn, so it is
    /// looked up by `Epic.current` rather than by today's `dayKey`. Done, it stays until Sunday.
    @ViewBuilder private var epicSection: some View {
        if let epic = currentEpic {
            Section {
                questRow(epic).swipeActions(edge: .trailing) {
                    rerollButton(epic)
                    extendButton(epic)
                    replaceEpicButton(epic)
                }
            } header: {
                Text("Epic · until \(Epic.lastDayKey(of: epic) ?? "Sunday")"
                     + (epic.extensionCount > 0 ? " · extended \(epic.extensionCount)/\(Epic.maxExtensions)" : ""))
            }
        }
    }

    /// Today's random slots.
    @ViewBuilder private var randomSection: some View {
        Section("Random slots") {
            if randomQuests.isEmpty {
                Text("No quests today — the pool is empty or fully on cooldown. The day is yours.")
                    .foregroundStyle(.secondary)
            }
            ForEach(randomQuests) { quest in
                if quest.replaced { replacedRow(quest) }
                else if quest.isTrivialGroup {
                    trivialGroupRow(quest).swipeActions(edge: .trailing) {
                        rerollButton(quest)
                        replaceButton(quest)
                    }
                } else {
                    questRow(quest).swipeActions(edge: .trailing) {
                        rerollButton(quest)
                        cancelQuestButton(quest)
                        replaceButton(quest)
                    }
                }
            }
        }
    }

    /// Nothing drawn means nothing to clear and no hidden reward to earn — then the section is
    /// hidden rather than showing a lock with no key.
    @ViewBuilder private var hiddenSection: some View {
        // Nothing was drawn, so there is nothing to clear and no hidden reward to earn —
        // the section is hidden rather than showing a lock with no key.
        if !randomQuests.isEmpty || hiddenQuest != nil {
            Section("Hidden") {
                if let hiddenQuest {
                    questRow(hiddenQuest)
                } else if hiddenUnlocked {
                    Button { revealHidden() } label: {
                        Label("Reveal the hidden quest", systemImage: "sparkles")
                            // Without this the tappable area is just the label's own box,
                            // which is a smaller target than the row it looks like.
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                } else {
                    Label("Clear every slot to unlock", systemImage: "lock")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The rest of the week's flexible work, folded away: sessions from earlier days still open
    /// (full pay until Sunday), what was pulled forward today, and what can be.
    @ViewBuilder private var aheadSection: some View {
        // The rest of the week's flexible work, folded: sessions from earlier days still
        // open (full pay until Sunday), what was pulled forward today, and what can be.
        // Saturday's session done today counts as Saturday's, and Saturday no longer carries it.
        if !thisWeekRoutines.isEmpty || !aheadCandidates.isEmpty || !doneAhead.isEmpty {
            Section {
                if aheadOpen {
                    ForEach(thisWeekRoutines) { o in
                        routineRow(o, note: .thisWeek).swipeActions(edge: .trailing) { replaceRoutineButton(o) }
                    }
                    ForEach(doneAhead) { doneAheadRow($0) }
                    ForEach(aheadCandidates, id: \.routine.id) { aheadRow($0) }
                }
            } header: {
                Button {
                    let open = !aheadOpen
                    withAnimation {
                        aheadExpanded = open
                        aheadToggledOn = today
                    }
                } label: {
                    HStack {
                        Text("Ahead this week")
                        Text("\(aheadPending)").monospacedDigit()
                        if !doneAhead.isEmpty {
                            Text("· \(doneAhead.count) done").monospacedDigit()
                        }
                        if weekEndBill > 0 {
                            Text("· −\(weekEndBill) Sun night").monospacedDigit().foregroundStyle(.red)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(aheadOpen ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Skipped and never done: a record rather than a to-do.
    private func backlogRow(_ o: RoutineOccurrence) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(o.textSnapshot).foregroundStyle(.secondary)
                Text("Due \(o.dueDayKey)").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            if o.penaltyApplied > 0 {
                Text("−\(o.penaltyApplied)").monospacedDigit().foregroundStyle(.red)
            }
        }
    }

    /// A flexible routine already done ahead of its due day.
    private func doneAheadRow(_ o: RoutineOccurrence) -> some View {
        HStack(alignment: .firstTextBaseline) {
            badge("R", range: nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(o.displayText)
                Text("Done ahead · counts for \(o.dueDayKey)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            let awarded = o.awardedPoints ?? 0
            Text("+\(awarded)").monospacedDigit().foregroundStyle(.green)
        }
    }

    /// A flexible routine that can be pulled forward. On a low day doing it ahead draws a lighter
    /// version, which is why the payout is a range rather than a number the draw could contradict.
    private func aheadRow(_ c: Schedule.Ahead) -> some View {
        HStack(alignment: .firstTextBaseline) {
            badge("R", range: aheadPayout(c.routine))
            VStack(alignment: .leading, spacing: 2) {
                Text(c.routine.text)
                Text("\(c.doneThisWeek)/\(c.routine.weeklyTarget) this week · next due \(c.nextDueDayKey)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Do now") { pending = .ahead(c.routine) }
                .buttonStyle(.bordered)
        }
    }

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
    /// The rule itself lives in Core; this only hands it the rows the query already has.
    private var streak: Int {
        Streak.current(days: Streak.completedDayKeys(allQuests),
                       frozen: Streak.frozenDayKeys(ledger), today: today)
    }
    private var hiddenUnlocked: Bool {
        (try? DayService.hiddenUnlocked(on: today, in: context)) ?? false
    }

    /// The page itself; the modifiers stay on `body`.
    private var questList: some View {
    List {
        if let generationError {
            Section { Text(generationError).foregroundStyle(.red) } header: { Text("Today could not be generated") }
        }
        if let actionError {
            Section { Text(actionError).foregroundStyle(.red) }
        }

        Section { hud } header: { Text(today) }

        epicSection

        routinesSection

        randomSection

        hiddenSection

        aheadSection

        // Skipped and never done: read-only, a record rather than a to-do.
        if !backlog.isEmpty {
            Section("Backlog") {
                ForEach(backlog) { backlogRow($0) }
            }
        }
    }
    }

    var body: some View {
        NavigationStack {
            questList
            // On the list, not beside the `fileExporter` below: two file presenters on one view
            // and only the last one ever shows.
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                prepareImport(result)
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add for today")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { prepareJSONExport() } label: {
                            Label("History (JSON)", systemImage: "clock.arrow.circlepath")
                        }
                        Button { prepareCSVExport() } label: {
                            Label("Ratings & comments (CSV)", systemImage: "star.bubble")
                        }
                        Divider()
                        Button { importing = true } label: {
                            Label("Restore from JSON…", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export or restore")
                }
            }
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
                Button("Spend \(spend.cost)") { buy(spend) }
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
            .fileExporter(isPresented: $exporting,
                          document: pendingExport,
                          contentType: pendingExport?.contentType ?? .json,
                          defaultFilename: pendingExport?.filename) { result in
                if case .failure(let error) = result { actionError = "Export failed: \(error)" }
                pendingExport = nil
            }
            .alert("Replace all history?", isPresented: Binding(
                get: { importPlan != nil }, set: { if !$0 { importPlan = nil } }
            ), presenting: importPlan) { plan in
                Button("Replace", role: .destructive) { performImport(plan) }
                Button("Cancel", role: .cancel) {}
            } message: { plan in
                Text(importMessage(plan.summary))
            }
        }
    }

    // MARK: HUD

    private var hud: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                // Negative is shown in red rather than clamped to zero — more honest.
                Text("\(balance)")
                    .font(.largeTitle.monospacedDigit().bold())
                    .foregroundStyle(balance < 0 ? .red : .primary)
                Text("coins").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Lv \(Economy.level(totalEarned: totalEarned))").font(.headline)
            }
            HStack(spacing: 16) {
                stat("Streak", "\(streak)d")
                stat("Next level", "\(Economy.pointsToNextLevel(totalEarned: totalEarned))")
                stat("Tier", tier.rawValue)
                stat("Slots", "\(todayContext?.randomSlots ?? 0)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func stat(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
            Text(value).monospacedDigit().foregroundStyle(.primary)
        }
    }

    // MARK: rows

    private func questRow(_ quest: DailyQuest) -> some View {
        HStack(alignment: .firstTextBaseline) {
            badge(quest.isHiddenSlot ? "★" : quest.slot.code,
                  range: Scoring.payoutRange(quest, tier: tier))
            VStack(alignment: .leading, spacing: 2) {
                Text(quest.textSnapshot)
                // The drawn value of a parameterized template, kept beside the wording rather
                // than spliced into it, so the CSV row stays recognisable in history.
                if let variant = quest.variantSnapshot, !variant.isEmpty {
                    Text(variant).font(.subheadline).foregroundStyle(.secondary)
                }
                if let url = quest.launchURLSnapshot, let link = URL(string: url) {
                    Link("Open", destination: link).font(.caption)
                }
            }
            Spacer()
            if let points = quest.points {
                Text("+\(points)").monospacedDigit().foregroundStyle(.green)
            } else {
                Button("Done") { pending = .quest(quest) }
                    .buttonStyle(.bordered)
            }
        }
    }

    private enum RoutineNote { case overdue, thisWeek }

    /// A routine pays a fixed amount, so the badge shows one number rather than a range — the
    /// same number `Completion.completeRoutine` will pay today (half for an overdue one).
    private func routineRow(_ occurrence: RoutineOccurrence, note: RoutineNote? = nil) -> some View {
        let flexible = isFlexible(occurrence)
        let pays = Completion.routinePayout(occurrence, flexible: flexible, on: today, tier: tier)
        return HStack(alignment: .firstTextBaseline) {
            badge("R", range: pays.map { $0...$0 })
            VStack(alignment: .leading, spacing: 2) {
                Text(occurrence.displayText)
                if occurrence.degradedTextSnapshot != nil { versionNote(occurrence) }
                if occurrence.completedDayKey == nil {
                    switch note {
                    case .overdue:
                        Text("Overdue −50%").font(.caption).foregroundStyle(.red)
                    case .thisWeek:
                        Text("Not done · due \(occurrence.dueDayKey)")
                            .font(.caption).foregroundStyle(.secondary)
                    case nil:
                        EmptyView()
                    }
                }
                if let questID = occurrence.replacesQuestID {
                    let replaced = allQuests.first { $0.id == questID }
                    Text("\(addedOn(occurrence)) · replaces \(replaced.map(slotText) ?? "a random slot")")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let replaced = occurrences.first(where: { $0.replacedByID == occurrence.id }) {
                    Text("Replaces \(replaced.displayText)").font(.caption).foregroundStyle(.secondary)
                } else if occurrence.routineID == nil {
                    // Added with + on top of the day (`AdHoc.add`): extra, never a liability.
                    Text("\(addedOn(occurrence)) · extra, no penalty").font(.caption).foregroundStyle(.secondary)
                }
                if !occurrence.countsForClear {
                    Text("Doesn't gate the hidden quest").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let points = occurrence.awardedPoints {
                Text("+\(points)").monospacedDigit().foregroundStyle(.green)
            } else if occurrence.skipped {
                Text("Skipped").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Done") { pending = .routine(occurrence) }
                    .buttonStyle(.bordered)
            }
        }
    }

    /// An ad-hoc occurrence still open from an earlier day is overdue like any other; its note
    /// shouldn't claim it was added today.
    private func addedOn(_ o: RoutineOccurrence) -> String {
        o.dueDayKey == today ? "Added today" : "Added \(o.dueDayKey)"
    }

    /// A routine with a light version on offer today: which one is chosen, and — while it is
    /// still open — a switch to the other. Both pay the same, so no confirmation.
    @ViewBuilder
    private func versionNote(_ occurrence: RoutineOccurrence) -> some View {
        let open = occurrence.completedDayKey == nil && !occurrence.skipped
        HStack(spacing: 6) {
            Text(occurrence.usedDegraded ? "Light version · \(occurrence.textSnapshot)"
                                         : "Original · light version available")
                .font(.caption).foregroundStyle(.secondary)
            if open {
                Button(occurrence.usedDegraded ? "Do original" : "Use light") {
                    do {
                        try Degrade.choose(light: !occurrence.usedDegraded, for: occurrence, in: context)
                        actionError = nil
                    } catch {
                        actionError = "\(error)"
                    }
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
    }

    private func replacedNote(_ reason: ReplacedReason) -> String {
        switch reason {
        case .replan: "Dropped — the day was re-planned"
        case .cancelled: "Cancelled"
        case .rerolled: "Rerolled away"
        case .adHoc: "Replaced"
        case .swapped: "Swapped"
        }
    }

    /// A slot that is no longer today's ask — taken over by an ad-hoc routine, dropped by a
    /// re-plan, or cancelled: kept on the page as a record, no longer to do.
    private func replacedRow(_ quest: DailyQuest) -> some View {
        HStack(alignment: .firstTextBaseline) {
            badge(quest.isTrivialGroup ? "T×3" : quest.slot.code)
            VStack(alignment: .leading, spacing: 2) {
                Text(slotText(quest)).strikethrough().foregroundStyle(.secondary)
                Text(replacedNote(quest.replacedReason))
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func slotText(_ quest: DailyQuest) -> String {
        quest.isTrivialGroup ? quest.trivialGroup.joined(separator: " · ") : quest.textSnapshot
    }

    /// Three micro-actions in one E slot, scored 12 as a whole once all three are ticked.
    private func trivialGroupRow(_ quest: DailyQuest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                badge("T×3", range: Scoring.payoutRange(quest, tier: tier))
                Text("Micro-actions").font(.subheadline.bold())
                Spacer()
                if let points = quest.points {
                    Text("+\(points)").monospacedDigit().foregroundStyle(.green)
                }
            }
            ForEach(Array(quest.trivialGroup.enumerated()), id: \.offset) { index, text in
                let done = quest.trivialDone.indices.contains(index) && quest.trivialDone[index]
                let variant = quest.trivialVariants.indices.contains(index) ? quest.trivialVariants[index] : ""
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(done ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(text).strikethrough(done)
                        if !variant.isEmpty {
                            Text(variant).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard quest.completedAt == nil, !done else { return }
                    pending = .trivialItem(quest, index)
                }
            }
        }
    }

    /// The difficulty code with what it can pay underneath — the stake, visible before you decide
    /// to do it rather than only in the reveal afterwards. The span comes from `Scoring`, tier
    /// multiplier and hidden bonus already applied, so it is the same arithmetic the roll obeys.
    private func badge(_ text: String, range: ClosedRange<Int>? = nil) -> some View {
        VStack(spacing: 0) {
            Text(text).font(.caption2.bold())
            if let range {
                Text(range.lowerBound == range.upperBound
                     ? "\(range.lowerBound)"
                     : "\(range.lowerBound)–\(range.upperBound)")
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 46)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
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

    // Swipe actions. Whether each can go through is Core's rule; when it can't, the button is
    // simply greyed out and shows no price.

    @ViewBuilder private func rerollButton(_ quest: DailyQuest) -> some View {
        if quest.completedAt == nil {
            spendButton(.reroll(quest), "Reroll", "dice", .orange,
                        open: Reroll.blocked(for: quest, on: today, balance: balance) == nil)
        }
    }

    @ViewBuilder private func extendButton(_ epic: DailyQuest) -> some View {
        if epic.completedAt == nil {
            spendButton(.extend(epic), "Extend", "calendar.badge.plus", .blue,
                        open: Epic.blocked(epic, on: today, balance: balance) == nil)
        }
    }

    /// Free — the price of an ad-hoc routine is that it now loses points if left undone — so it
    /// only appears where it applies rather than sitting greyed out on every row.
    @ViewBuilder private func replaceButton(_ quest: DailyQuest) -> some View {
        if replaceableIDs.contains(quest.id) {
            Button { replacing = quest } label: {
                Label("Replace", systemImage: "arrow.triangle.swap")
            }
            .tint(.indigo)
        }
    }

    /// Free, for something at least as heavy (`AdHoc.replaceRoutine`); only where it applies.
    @ViewBuilder private func replaceRoutineButton(_ o: RoutineOccurrence) -> some View {
        if AdHoc.isReplaceable(o, flexible: isFlexible(o), on: today) {
            Button { replacingRoutine = o } label: {
                Label("Replace", systemImage: "arrow.triangle.swap")
            }
            .tint(.indigo)
        }
    }

    /// Free (`Epic.replace`); gone once the epic is done or extended.
    @ViewBuilder private func replaceEpicButton(_ epic: DailyQuest) -> some View {
        if Epic.blockedReplace(epic, on: today) == nil {
            Button { replacingEpic = epic } label: {
                Label("Replace", systemImage: "arrow.triangle.swap")
            }
            .tint(.indigo)
        }
    }

    @ViewBuilder private func cancelQuestButton(_ quest: DailyQuest) -> some View {
        if quest.completedAt == nil, Redemption.cancelCost(for: quest.slot) != nil {
            spendButton(.cancelQuest(quest), "Cancel", "xmark", .red,
                        open: Redemption.blocked(cancelling: quest, on: today, balance: balance) == nil)
        }
    }

    /// Only the routines a cancel can apply to get the button at all — a flexible one or a
    /// check-in never could, so a permanently grey button there would just be noise.
    @ViewBuilder private func cancelRoutineButton(_ o: RoutineOccurrence) -> some View {
        let blocked = Redemption.blocked(cancelling: o, flexible: isFlexible(o), on: today, balance: balance)
        if blocked != .notAvailable, blocked != .alreadyCompleted {
            spendButton(.cancelRoutine(o), "Cancel", "xmark", .red, open: blocked == nil)
        }
    }

    private func spendButton(_ spend: Spend, _ name: String, _ icon: String, _ color: Color,
                             open: Bool) -> some View {
        Button { spending = spend } label: {
            Label(open ? "\(name) · \(spend.cost)" : name, systemImage: icon)
        }
        .tint(open ? color : .gray)
        .disabled(!open)
    }

    private func message(for spend: Spend) -> String {
        switch spend {
        case .reroll(let q):
            "\(slotText(q))\n\n" + (q.slot == .epic
                ? "Swap it for a different epic for \(spend.cost) coins. It keeps the same deadline. Once extended, an epic can't be rerolled."
                : "Swap it for a different \(q.slot.code) for \(spend.cost) coins. The next reroll of this slot today costs more.")
        case .extend(let q):
            "\(q.textSnapshot)\n\nOne more week, for \(spend.cost) coins. The week it runs into gets no new epic, and it can't be rerolled or replaced any more."
        case .cancelQuest(let q):
            "\(slotText(q))\n\nDrop it for \(spend.cost) coins. It no longer blocks the hidden quest, but it earns nothing and doesn't count toward the streak."
        case .cancelRoutine(let o):
            "\(o.displayText)\n\nDrop it for \(spend.cost) coins. No more overdue deductions, and it no longer blocks the hidden quest. Deductions already charged stay."
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

    private func prepareJSONExport() {
        export { .json(try JSONExport.data(context), name: JSONExport.filename()) }
    }

    private func prepareCSVExport() {
        export { .folder(try CSVExport.files(context), name: CSVExport.folderName()) }
    }

    /// Reads and maps the file; writes nothing — the alert asks first.
    private func prepareImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            importPlan = try JSONImport.plan(try Data(contentsOf: url), against: context)
            actionError = nil
        } catch {
            actionError = "Import failed: \(error)"
        }
    }

    private func performImport(_ plan: JSONImport.Plan) {
        do {
            try JSONImport.apply(plan, to: context)
            actionError = nil
            onImported()
        } catch {
            actionError = "Import failed: \(error)"
        }
    }

    private func importMessage(_ s: JSONImport.Summary) -> String {
        let days = [s.firstDayKey, s.lastDayKey].compactMap { $0 }
        var lines = [
            "Backup exported \(s.exportedAt.formatted(date: .abbreviated, time: .shortened))"
                + (days.isEmpty ? "" : ", covering \(days.joined(separator: " – "))") + ".",
            "\(s.dailyQuests) quests, \(s.routineOccurrences) routines, \(s.ledgerEntries) ledger entries, "
                + "\(s.ratings) ratings, \(s.comments) comments, \(s.rewards) rewards.",
            "Balance after restoring: \(s.balance).",
            "Everything in this app's history is replaced by the backup.",
        ]
        if !s.unmatchedLibrary.isEmpty {
            lines.append("\(s.unmatchedLibrary.count) quest(s) or routine(s) in the backup aren't in this library; "
                         + "their history is kept but won't link back.")
        }
        return lines.joined(separator: "\n\n")
    }

    /// Builds the document, then opens the system save dialog. The dialog is a separate process
    /// and can take a second or two to come up the first time — it is not instant.
    private func export(_ build: () throws -> ExportDocument) {
        do {
            pendingExport = try build()
            exporting = true
        } catch {
            actionError = "Export failed: \(error)"
        }
    }
}

/// Anything the page exports: the JSON history dump, or the feedback logs as a folder of CSVs.
/// One document type, because one `fileExporter` has to be able to present either.
/// Export only — the JSON comes back in through `fileImporter` and `JSONImport`, not this type.
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .folder] }

    let contentType: UTType
    let filename: String
    private let wrapper: FileWrapper

    static func json(_ data: Data, name: String) -> ExportDocument {
        ExportDocument(contentType: .json, filename: name,
                       wrapper: FileWrapper(regularFileWithContents: data))
    }

    static func folder(_ files: [CSVExport.File], name: String) -> ExportDocument {
        var children: [String: FileWrapper] = [:]
        for file in files {
            children[file.name] = FileWrapper(regularFileWithContents: Data(file.contents.utf8))
        }
        return ExportDocument(contentType: .folder, filename: name,
                              wrapper: FileWrapper(directoryWithFileWrappers: children))
    }

    private init(contentType: UTType, filename: String, wrapper: FileWrapper) {
        self.contentType = contentType
        self.filename = filename
        self.wrapper = wrapper
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { wrapper }
}

#Preview {
    TodayView(today: Date().dayKey, generationError: nil)
        .modelContainer(for: LifeRPGSchema.models, inMemory: true)
}
