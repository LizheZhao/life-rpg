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

    @Environment(\.modelContext) private var context

    // Small tables (a handful of rows per day), so the whole set is queried and filtered here
    // rather than rebuilding a predicate every time the day rolls over.
    @Query(sort: \DailyQuest.dayKey) private var allQuests: [DailyQuest]
    @Query private var ledger: [LedgerEntry]
    @Query private var contexts: [DailyContext]
    @Query private var occurrences: [RoutineOccurrence]
    @Query private var routines: [RoutineTask]

    @State private var pending: PendingAction?
    /// Collapsed by default: it lists every flexible routine still short this week, which is most
    /// of them early in the week, and none of it is today's work.
    @AppStorage("aheadExpanded") private var aheadExpanded = false
    @State private var addingAdHoc = false
    @State private var roll: Roll?
    @State private var actionError: String?
    @State private var exportingJSON = false
    @State private var exportingCSV = false
    @State private var jsonDocument: JSONSnapshotDocument?
    @State private var csvDocument: FeedbackCSVDocument?

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
    private var onCycle: Bool { todayContext?.onCycle ?? false }
    /// The day's measured state, as stored. Both completion scoring and the hidden draw read this
    /// same value — a hidden quest drawn under `normal` rules on a very-low day would hand out the
    /// hardest thing in the pool as the reward for a day you barely got through.
    private var inputs: DayInputs { DayInputs(tier: tier, onCycle: onCycle) }

    private var quests: [DailyQuest] { allQuests.filter { $0.dayKey == today } }
    /// Easy first, the way the composition table is written — the query itself has no order
    /// beyond `dayKey`, so without this the rows shuffle on every regeneration.
    private var randomQuests: [DailyQuest] {
        quests.filter { !$0.isHiddenSlot }
            .sorted { a, b in
                let ra = Difficulty.allCases.firstIndex(of: a.slot) ?? 0
                let rb = Difficulty.allCases.firstIndex(of: b.slot) ?? 0
                return ra == rb ? a.textSnapshot < b.textSnapshot : ra < rb
            }
    }
    private var hiddenQuest: DailyQuest? { quests.first(where: \.isHiddenSlot) }

    private var todaysRoutines: [RoutineOccurrence] {
        occurrences.filter { $0.dueDayKey == today }.sorted { $0.textSnapshot < $1.textSnapshot }
    }
    private var flexibleIDs: Set<UUID> { Set(routines.filter(\.flexibleWithinWeek).map(\.id)) }
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
        Streak.current(days: Streak.completedDayKeys(allQuests), today: today)
    }
    private var hiddenUnlocked: Bool {
        (try? DayService.hiddenUnlocked(on: today, in: context)) ?? false
    }

    var body: some View {
        NavigationStack {
            List {
                if let generationError {
                    Section { Text(generationError).foregroundStyle(.red) } header: { Text("Today could not be generated") }
                }
                if let actionError {
                    Section { Text(actionError).foregroundStyle(.red) }
                }

                Section { hud } header: { Text(today) }

                // Only what is on today: due today, plus fixed routines that are overdue — those
                // cost points every day they stay undone, so they are never folded away.
                if !overdueRoutines.isEmpty || !todaysRoutines.isEmpty {
                    Section("Routines") {
                        ForEach(overdueRoutines) { routineRow($0, note: .overdue) }
                        ForEach(todaysRoutines) { routineRow($0) }
                    }
                }

                Section("Random slots") {
                    if randomQuests.isEmpty {
                        Text("No quests today — the pool is empty or fully on cooldown. The day is yours.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(randomQuests) { quest in
                        if quest.replaced { replacedRow(quest) }
                        else if quest.isTrivialGroup { trivialGroupRow(quest) } else { questRow(quest) }
                    }
                }

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

                // The rest of the week's flexible work, folded: sessions from earlier days still
                // open (full pay until Sunday), what was pulled forward today, and what can be.
                // Saturday's session done today counts as Saturday's, and Saturday no longer carries it.
                if !thisWeekRoutines.isEmpty || !aheadCandidates.isEmpty || !doneAhead.isEmpty {
                    Section {
                        if aheadExpanded {
                            ForEach(thisWeekRoutines) { routineRow($0, note: .thisWeek) }
                            ForEach(doneAhead) { o in
                                HStack(alignment: .firstTextBaseline) {
                                    badge("R", range: nil)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(o.displayText)
                                        Text("Done ahead · counts for \(o.dueDayKey)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("+\(o.awardedPoints ?? 0)").monospacedDigit().foregroundStyle(.green)
                                }
                            }
                            ForEach(aheadCandidates, id: \.routine.id) { c in
                                let pays = Scoring.routinePoints(basePoints: c.routine.basePoints, tier: tier, late: false)
                                HStack(alignment: .firstTextBaseline) {
                                    badge("R", range: pays...pays)
                                    VStack(alignment: .leading, spacing: 2) {
                                        // On a low day doing it ahead creates the light version.
                                        Text(Degrade.text(for: c.routine, tier: tier) ?? c.routine.text)
                                        Text("\(c.doneThisWeek)/\(c.routine.weeklyTarget) this week · next due \(c.nextDueDayKey)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Do now") { pending = .ahead(c.routine) }
                                        .buttonStyle(.bordered)
                                }
                            }
                        }
                    } header: {
                        Button {
                            withAnimation { aheadExpanded.toggle() }
                        } label: {
                            HStack {
                                Text("Ahead this week")
                                Text("\(thisWeekRoutines.count + aheadCandidates.count)").monospacedDigit()
                                if !doneAhead.isEmpty {
                                    Text("· \(doneAhead.count) done").monospacedDigit()
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .rotationEffect(.degrees(aheadExpanded ? 90 : 0))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Skipped and never done: read-only, a record rather than a to-do.
                if !backlog.isEmpty {
                    Section("Backlog") {
                        ForEach(backlog) { o in
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
                    }
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { addingAdHoc = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add a routine for today")
                        .disabled(AdHoc.replaceableSlots(quests, on: today).isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { prepareJSONExport() } label: {
                            Label("History (JSON)", systemImage: "clock.arrow.circlepath")
                        }
                        Button { prepareCSVExport() } label: {
                            Label("Ratings & comments (CSV)", systemImage: "star.bubble")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export")
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
                // version is picked here. Same points either way.
                if case .ahead(let routine) = action, Degrade.text(for: routine, tier: tier) != nil {
                    Button("Did the light version") { perform(action, light: true) }
                    Button("Did the original") { perform(action, light: false) }
                } else {
                    Button("Complete") { perform(action) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { action in
                if case .ahead(let routine) = action, let light = Degrade.text(for: routine, tier: tier) {
                    Text("\(routine.text)\nLight version: \(light)\n\nSame points either way. This is final — completion cannot be undone.")
                } else {
                    Text("\(action.label)\n\nThis is final — completion cannot be undone.")
                }
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
            .sheet(isPresented: $addingAdHoc) {
                AdHocView(today: today, tier: tier)
            }
            .fileExporter(isPresented: $exportingJSON,
                          document: jsonDocument,
                          contentType: .json,
                          defaultFilename: JSONExport.filename()) { result in
                if case .failure(let error) = result { actionError = "Export failed: \(error)" }
                jsonDocument = nil
            }
            .fileExporter(isPresented: $exportingCSV,
                          document: csvDocument,
                          contentType: .folder,
                          defaultFilename: CSVExport.folderName()) { result in
                if case .failure(let error) = result { actionError = "Export failed: \(error)" }
                csvDocument = nil
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
        let flexible = occurrence.routineID.map(flexibleIDs.contains) ?? false
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
                    Text("Added today · replaces \(replaced.map(slotText) ?? "a random slot")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !occurrence.countsForClear {
                    Text("Doesn't gate the hidden quest").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let points = occurrence.awardedPoints {
                Text("+\(points)").monospacedDigit().foregroundStyle(.green)
            } else {
                Button("Done") { pending = .routine(occurrence) }
                    .buttonStyle(.bordered)
            }
        }
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

    /// A slot an ad-hoc routine took over: kept on the page as a record, no longer to do.
    private func replacedRow(_ quest: DailyQuest) -> some View {
        HStack(alignment: .firstTextBaseline) {
            badge(quest.isTrivialGroup ? "T×3" : quest.slot.code)
            VStack(alignment: .leading, spacing: 2) {
                Text(slotText(quest)).strikethrough().foregroundStyle(.secondary)
                Text("Replaced").font(.caption).foregroundStyle(.tertiary)
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
                        dayKey: quest.dayKey)
        }
    }

    /// Rating is never required, so a failure here must not interrupt anything — the points are
    /// already banked and the quest is already done.
    private func record(rating: Int, for roll: Roll) {
        Feedback.rate(context, target: .quest, id: roll.templateID, questID: roll.questID,
                      text: roll.text, rating: rating, dayKey: roll.dayKey)
        try? context.save()
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
        do {
            jsonDocument = JSONSnapshotDocument(data: try JSONExport.data(context))
            exportingJSON = true
        } catch {
            actionError = "Export failed: \(error)"
        }
    }

    private func prepareCSVExport() {
        do {
            csvDocument = FeedbackCSVDocument(files: try CSVExport.files(context))
            exportingCSV = true
        } catch {
            actionError = "Export failed: \(error)"
        }
    }
}

/// The JSON history dump, wrapped for `fileExporter`. Export only — import lands in Stage 6.
struct JSONSnapshotDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    TodayView(today: Date().dayKey, generationError: nil)
        .modelContainer(for: LifeRPGSchema.models, inMemory: true)
}
