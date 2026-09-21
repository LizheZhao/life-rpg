import LifeRPGCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The daily page: HUD, today's random slots, and the hidden quest once the day is cleared.
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

    @State private var pending: PendingAction?
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

        var label: String {
            switch self {
            case .quest(let q): [q.textSnapshot, q.variantSnapshot]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
            case .trivialItem(let q, let i): q.trivialGroup.indices.contains(i) ? q.trivialGroup[i] : ""
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

                Section("Random slots") {
                    if randomQuests.isEmpty {
                        Text("No quests today — the pool is empty or fully on cooldown. The day is yours.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(randomQuests) { quest in
                        if quest.isTrivialGroup { trivialGroupRow(quest) } else { questRow(quest) }
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
            }
            .navigationTitle("Today")
            .toolbar {
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
                Button("Complete") { perform(action) }
                Button("Cancel", role: .cancel) {}
            } message: { action in
                Text("\(action.label)\n\nThis is final — completion cannot be undone.")
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

    private func perform(_ action: PendingAction) {
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
