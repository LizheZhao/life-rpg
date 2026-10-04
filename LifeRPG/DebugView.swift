import LifeRPGCore
import SwiftData
import SwiftUI

/// Debug page: row counts per table and the data audit. Not part of daily use — it is how a
/// failed seed or an unreadable raw value gets noticed at all.
struct DebugView: View {
    let seedStatus: String
    /// The app's current day — shifted by time travel on the simulator.
    let today: String
    /// What the last refresh read from HealthKit and the calendar.
    var sensorReport: String = ""
    /// Re-runs the root refresh: re-reads evidence and auto-verifies today.
    var refresh: () async -> Void = {}
    #if targetEnvironment(simulator)
    @AppStorage("debugDayOffset") private var dayOffset = 0
    /// "evening" or "daytime" overrides the clock Today reads for the journal card; "" is the real one.
    @AppStorage("debugJournalTiming") private var journalTiming = ""
    /// What the last press of the hand-off button returned: "" is a text that came back empty.
    @State private var handOffText: String?
    @State private var trendsSeedText: String?
    #else
    /// Time travel is simulator-only; on a device the day is today (as in `RootView`).
    private let dayOffset = 0
    #endif

    @Environment(\.modelContext) private var modelContext
    @State private var audit: [StoreAudit.Issue] = []
    @State private var auditError: String?
    @State private var confirmingReset = false
    @State private var confirmingWholeReset = false
    @State private var resetResult: String?
    @State private var permissionError: String?
    @State private var preview: HealthService.Body?
    @State private var previewError: String?
    /// Visible feedback for the two HealthKit buttons — without it, "denied", "no data" and
    /// "still running" all look like a button that did nothing.
    @State private var healthStatus: String?
    @State private var copied = false

    @Query private var questTemplates: [QuestTemplate]
    @Query private var routineTasks: [RoutineTask]
    @Query private var dailyQuests: [DailyQuest]
    @Query private var routineOccurrences: [RoutineOccurrence]
    @Query private var rewards: [Reward]
    @Query private var ledgerEntries: [LedgerEntry]
    @Query private var dailyContexts: [DailyContext]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LR.Spacing.sectionGap) {
                section("Seed") {
                    Text(seedStatus).font(Self.mono).foregroundStyle(LR.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                bodySection
                section("Journal model") {
                    Text(JournalWordingProvider.status()).font(Self.mono).foregroundStyle(LR.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                section("Tables") {
                    row("QuestTemplate", questTemplates.count,
                        detail: "\(questTemplates.filter(\.isActive).count) active")
                    rule
                    row("RoutineTask", routineTasks.count,
                        detail: "\(routineTasks.filter(\.isActive).count) active")
                    rule
                    row("DailyQuest", dailyQuests.count)
                    rule
                    row("RoutineOccurrence", routineOccurrences.count)
                    rule
                    row("Reward", rewards.count)
                    rule
                    row("LedgerEntry", ledgerEntries.count)
                    rule
                    row("DailyContext", dailyContexts.count)
                }
                // The enum getters fall back (`?? .easy`), so an unreadable raw value would
                // otherwise be invisible. Nothing from the CSV can land here — the seed parser
                // rejects it — but a JSON import or an enum rename could.
                section("Data audit") {
                    if let auditError {
                        Text(auditError).font(Self.mono).foregroundStyle(LR.Color.clay)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if audit.isEmpty {
                        Label("No unreadable values", systemImage: "checkmark.circle")
                            .lr(.bodyStrong).foregroundStyle(LR.Color.inkSecondary)
                    } else {
                        ForEach(Array(audit.enumerated()), id: \.element.description) { index, issue in
                            if index > 0 { rule }
                            row("\(issue.model).\(issue.field) = '\(issue.value)'", issue.count, clay: true)
                        }
                    }
                }
                // Deliberately here and not on the today page: `PLAN.md` §3 makes completion
                // final, and a reset button sitting next to the quests would undo that rule in
                // practice whatever the doc says. This is for exercising the payout roll while
                // it is being built, not for changing your mind.
                section("Testing", footer: "Reset today puts the day back as if it had just been opened: everything dated today (quests, routines, extras, what was done ahead) is removed with its payouts, ratings and notes, and the day is drawn again. Reopen quests only undoes the day's results: the same quests come back, undone. Other days are untouched.") {
                    FlowRow(spacing: 8) {
                        Button { confirmingWholeReset = true } label: {
                            Label("Reset today", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(ClayPillButtonStyle())
                        Button { confirmingReset = true } label: {
                            Label("Reopen quests", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(ClayPillButtonStyle())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let resetResult { note(resetResult) }
                }

                #if targetEnvironment(simulator)
                section("Time travel (simulator only)", footer: "Each step is like opening the app the next morning: yesterday is judged, today is generated. Going back does not undo anything — future days stay generated. To start clean, delete the app from the simulator.") {
                    value("App day", dayOffset == 0 ? today : "\(today)  (+\(dayOffset))")
                    FlowRow(spacing: 8) {
                        Button { dayOffset += 1 } label: {
                            Label("Advance one day", systemImage: "forward.frame")
                        }
                        .buttonStyle(PillButtonStyle())
                        Button { dayOffset = 0 } label: {
                            Label("Back to the real date", systemImage: "calendar")
                        }
                        .buttonStyle(PillButtonStyle())
                        .disabled(dayOffset == 0)
                    }
                }
                section("Journal timing (simulator only)", footer: "Today shows the journal's evening card from 18:00 and a book icon with a dot in the daytime. This forces one of them so both can be seen at any hour.") {
                    PillSegmentedControl(options: [("Real clock", ""), ("Evening", "evening"), ("Daytime", "daytime")],
                                         selection: $journalTiming, accessibilityLabel: "Journal timing")
                }
                section("Trends fixture (simulator only)", footer: "Writes journal entries for the 60 (or 365) days before the app's day, with a day setting and some done quests and routines to go with them, so the Trends page has something to show. None of it came from using the app; pressing it again rewrites the same entries.") {
                    FlowRow(spacing: 8) {
                        Button { seedTrends(days: 60) } label: {
                            Label("Seed 60 journal days", systemImage: "text.badge.plus")
                        }
                        .buttonStyle(PillButtonStyle())
                        Button { seedTrends(days: 365) } label: {
                            Label("Seed a year", systemImage: "text.badge.plus")
                        }
                        .buttonStyle(PillButtonStyle())
                    }
                    if let trendsSeedText { note(trendsSeedText) }
                }
                section("Journal hand-off (simulator only)", footer: "The Shortcut can not be run here. This calls what Get Journal Text to Send calls, at the shifted clock above, so a press with the day written one day behind returns that day and marks it sent; a second press returns nothing.") {
                    Button { runHandOff() } label: {
                        Label("Run Get Journal Text to Send now", systemImage: "paperplane")
                    }
                    .buttonStyle(PillButtonStyle())
                    if let handOffText {
                        Text(handOffText.isEmpty ? "(empty text)" : handOffText)
                            .font(Self.mono).foregroundStyle(LR.Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                #endif

                section("Quests by difficulty") {
                    ForEach(Array(Difficulty.allCases.enumerated()), id: \.element) { index, d in
                        if index > 0 { rule }
                        row(d.rawValue, questTemplates.filter { $0.difficulty == d }.count)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .reservingTabBarSpace()
        .background(LR.Color.canvas.ignoresSafeArea())
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { audit = try StoreAudit.issues(modelContext) }
            catch { auditError = "Audit failed: \(error)" }
        }
        .alert("Reopen today's quests?", isPresented: $confirmingReset) {
            Button("Reopen", role: .destructive) { reopenToday() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Today's quest completions and the points they paid are deleted; the same quests come back. Routines are not touched. Other days are untouched.")
        }
        .alert("Reset today?", isPresented: $confirmingWholeReset) {
            Button("Reset", role: .destructive) { resetToday() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everything dated today is removed with its payouts, ratings and notes, and the day is drawn again. Other days are untouched.")
        }
    }

    // MARK: layout

    private static let mono = Font.system(.footnote, design: .monospaced)

    /// A header in the Settings style, one card of rows, and the explanation under it.
    private func section<Content: View>(_ title: LocalizedStringKey, footer: LocalizedStringKey? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).lr(.heading).foregroundStyle(LR.Color.sectionTitle)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 12, content: content)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lrCard(.surface, radius: LR.Radius.row)
            if let footer {
                Text(footer).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var rule: some View {
        Rectangle().fill(LR.Color.divider).frame(height: 1).accessibilityHidden(true)
    }

    private func note(_ text: String, clay: Bool = false) -> some View {
        Text(text).lr(.caption).foregroundStyle(clay ? LR.Color.clay : LR.Color.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Stage 3 — body and calendar

    private var todayContext: DailyContext? { dailyContexts.first { $0.dayKey == today } }

    private var bodySection: some View {
        section("Body (today)", footer: "The tier is set when the day is generated — the first time the app opens that day — but the body is read again on every foreground. If a later reading disagrees, the app offers to re-plan what is still open; finished work is never touched. Cycle days 1–3 hold the tier at low. A metric with no data is left out; with none at all the day is normal.") {
            if let day = todayContext {
                value("Tier", day.tier.rawValue + (day.cycleDay.map { " (cycle day \($0))" } ?? (day.onCycle ? " (cycle)" : "")))
                value("Energy / readiness", String(format: "%.3f / %d", day.energy, day.readiness))
                value("HRV", day.hrv.map { String(format: "%.1f ms", $0) } ?? "—")
                value("Sleep", day.sleepHours.map { String(format: "%.2f h", $0) } ?? "—")
                value("Resting HR", day.restingHR.map { String(format: "%.0f bpm", $0) } ?? "—")
                rule
            }
            sensorCard
            Button {
                healthStatus = "Requesting Health access…"
                Task {
                    do {
                        try await HealthService().requestAuthorization()
                        permissionError = nil
                        healthStatus = "Health request finished at \(clock()). No sheet = already answered once; change it in Settings → Health → Data Access & Devices → LifeRPG."
                    } catch {
                        permissionError = "Health: \(error.localizedDescription)"
                        healthStatus = nil
                    }
                    await refresh()
                }
            } label: {
                Label("Allow Health access", systemImage: "heart.text.square")
            }
            .buttonStyle(PillButtonStyle())
            .disabled(!HealthService.isAvailable)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let permissionError { note(permissionError, clay: true) }
            Button {
                healthStatus = "Reading HealthKit…"
                Task {
                    do {
                        preview = try await HealthService().body(for: today, now: Date())
                        previewError = nil
                        healthStatus = "Read at \(clock())"
                    } catch {
                        previewError = error.localizedDescription
                        healthStatus = nil
                    }
                }
            } label: {
                Label("Preview today's body data", systemImage: "waveform.path.ecg")
            }
            .buttonStyle(PillButtonStyle())
            .disabled(!HealthService.isAvailable)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let healthStatus { note(healthStatus) }
            if let previewError { note(previewError, clay: true) }
            if let preview { previewRows(preview) }
        }
    }

    /// What the last refresh read, in a monospaced block with a copy button, so it can be pasted
    /// into a bug report whole.
    private var sensorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(sensorReport).font(Self.mono).foregroundStyle(LR.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Button {
                UIPasteboard.general.string = sensorReport
                Haptics.selection()
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy report", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(PillButtonStyle())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: LR.Radius.pill + 4, style: .continuous).fill(LR.Color.pillFill))
        .onChange(of: sensorReport) { copied = false }
    }

    /// Read now, not stored: the day's tier stays whatever it was locked at.
    @ViewBuilder
    private func previewRows(_ p: HealthService.Body) -> some View {
        let i = p.inputs
        rule
        value("Preview tier", i.tier.rawValue + (i.onCycle ? " (cycle day)" : ""))
        value("Preview energy / readiness", String(format: "%.3f / %d", i.energy, i.readiness))
        value("HRV (baseline)", pair(p.today.hrv, p.baseline.hrv, "%.1f"))
        value("Sleep h (baseline)", pair(p.today.sleepHours, p.baseline.sleepHours, "%.2f"))
        value("Resting HR (baseline)", pair(p.today.restingHR, p.baseline.restingHR, "%.0f"))
        note("Preview only — not saved. Baseline \"—\" means fewer than \(Energy.minimumDays) days of that metric in the last \(Energy.window).")
    }

    private func clock() -> String {
        Date().formatted(date: .omitted, time: .standard)
    }

    private func pair(_ today: Double?, _ baseline: Double?, _ format: String) -> String {
        let f = { (v: Double?) in v.map { String(format: format, $0) } ?? "—" }
        return "\(f(today)) (\(f(baseline)))"
    }

    private func value(_ name: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
            Spacer(minLength: 8)
            Text(text).font(Self.mono).foregroundStyle(LR.Color.ink).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func row(_ name: String, _ count: Int, detail: String? = nil, clay: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name).lr(.bodyStrong).foregroundStyle(clay ? LR.Color.clay : LR.Color.ink)
            Spacer(minLength: 8)
            if let detail { Text(detail).lr(.caption).foregroundStyle(LR.Color.inkSecondary) }
            Text("\(count)").font(Self.mono).foregroundStyle(clay ? LR.Color.clay : LR.Color.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private func resetToday() {
        do {
            // The same clock the day is opened with, so a simulator day offset resets that day.
            let now = LifeCalendar.gregorian().date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
            var rng = SystemRandomNumberGenerator()
            let result = try DayReset.reset(modelContext, dayKey: today, now: now, rng: &rng)
            resetResult = result.description
            audit = try StoreAudit.issues(modelContext)
        } catch {
            resetResult = "Reset failed: \(error)"
        }
    }

    #if targetEnvironment(simulator)
    private func seedTrends(days: Int) {
        do {
            let seeded = try TrendsSeed.seed(days: days, endingBefore: today, in: modelContext)
            trendsSeedText = "Wrote \(seeded.entries) entries, \(seeded.contexts) day settings, "
                + "\(seeded.quests) quests and \(seeded.routines) routines before \(today)."
        } catch {
            trendsSeedText = "Seed failed: \(error)"
        }
    }

    private func runHandOff() {
        let now = LifeCalendar.gregorian().date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        do { handOffText = try JournalHandOff.textToSend(now: now, in: modelContext) }
        catch { handOffText = "Failed: \(error)" }
    }
    #endif

    private func reopenToday() {
        do {
            let result = try DayReset.reopen(modelContext, dayKey: today)
            resetResult = result.description
            audit = try StoreAudit.issues(modelContext)
        } catch {
            resetResult = "Reopen failed: \(error)"
        }
    }
}

/// The light capsule of `PillButtonStyle` for the one destructive button, in clay.
private struct ClayPillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lr(.bodyStrong)
            .foregroundStyle(LR.Color.clay)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(LR.Color.clayBg))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed || !isEnabled ? 0.6 : 1)
    }
}

#Preview {
    NavigationStack { DebugView(seedStatus: "Preview", today: Date().dayKey) }
        .modelContainer(for: LifeRPGSchema.models, inMemory: true)
}
