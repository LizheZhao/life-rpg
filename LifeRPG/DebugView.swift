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
    var refresh: () -> Void = {}
    #if targetEnvironment(simulator)
    @AppStorage("debugDayOffset") private var dayOffset = 0
    #endif

    @Environment(\.modelContext) private var modelContext
    @State private var audit: [StoreAudit.Issue] = []
    @State private var auditError: String?
    @State private var confirmingReset = false
    @State private var resetResult: String?
    @State private var permissionError: String?
    @State private var preview: HealthService.Body?
    @State private var previewError: String?
    /// Visible feedback for the two HealthKit buttons — without it, "denied", "no data" and
    /// "still running" all look like a button that did nothing.
    @State private var healthStatus: String?
    @State private var calendars: [(id: String, title: String)] = []
    @AppStorage("workoutCalendarID") private var workoutCalendarID = ""
    @AppStorage("workoutKeywords") private var workoutKeywords = ""

    @Query private var questTemplates: [QuestTemplate]
    @Query private var routineTasks: [RoutineTask]
    @Query private var dailyQuests: [DailyQuest]
    @Query private var routineOccurrences: [RoutineOccurrence]
    @Query private var rewards: [Reward]
    @Query private var ledgerEntries: [LedgerEntry]
    @Query private var dailyContexts: [DailyContext]

    var body: some View {
        NavigationStack {
            List {
                Section("Seed") {
                    Text(seedStatus)
                }
                bodySection
                workoutSection
                Section("Tables") {
                    row("QuestTemplate", questTemplates.count,
                        detail: "\(questTemplates.filter(\.isActive).count) active")
                    row("RoutineTask", routineTasks.count,
                        detail: "\(routineTasks.filter(\.isActive).count) active")
                    row("DailyQuest", dailyQuests.count)
                    row("RoutineOccurrence", routineOccurrences.count)
                    row("Reward", rewards.count)
                    row("LedgerEntry", ledgerEntries.count)
                    row("DailyContext", dailyContexts.count)
                }
                // The enum getters fall back (`?? .easy`), so an unreadable raw value would
                // otherwise be invisible. Nothing from the CSV can land here — the seed parser
                // rejects it — but a JSON import or an enum rename could.
                Section("Data audit") {
                    if let auditError {
                        Text(auditError).foregroundStyle(.red)
                    } else if audit.isEmpty {
                        Label("No unreadable values", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(audit, id: \.description) { issue in
                            row("\(issue.model).\(issue.field) = '\(issue.value)'", issue.count)
                                .foregroundStyle(.red)
                        }
                    }
                }
                // Deliberately here and not on the today page: `PLAN.md` §3 makes completion
                // final, and a reset button sitting next to the quests would undo that rule in
                // practice whatever the doc says. This is for exercising the payout roll while
                // it is being built, not for changing your mind.
                Section {
                    Button(role: .destructive) { confirmingReset = true } label: {
                        Label("Reopen today", systemImage: "arrow.counterclockwise")
                    }
                    if let resetResult {
                        Text(resetResult).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Testing")
                } footer: {
                    Text("Marks today's quests undone, deletes the ledger entries that paid for them, and removes the hidden quest so it can be revealed again. The same quests come back — only the day's results are undone.")
                }

                #if targetEnvironment(simulator)
                Section {
                    HStack {
                        Text("App day")
                        Spacer()
                        Text(dayOffset == 0 ? today : "\(today)  (+\(dayOffset))").monospacedDigit()
                    }
                    Button { dayOffset += 1 } label: {
                        Label("Advance one day", systemImage: "forward.frame")
                    }
                    Button { dayOffset = 0 } label: {
                        Label("Back to the real date", systemImage: "calendar")
                    }
                    .disabled(dayOffset == 0)
                } header: {
                    Text("Time travel (simulator only)")
                } footer: {
                    Text("Each step is like opening the app the next morning: yesterday is judged, today is generated. Going back does not undo anything — future days stay generated. To start clean, delete the app from the simulator.")
                }
                #endif

                Section("Quests by difficulty") {
                    ForEach(Difficulty.allCases, id: \.self) { d in
                        row(d.rawValue, questTemplates.filter { $0.difficulty == d }.count)
                    }
                }
            }
            .navigationTitle("Debug")
            .task {
                do { audit = try StoreAudit.issues(modelContext) }
                catch { auditError = "Audit failed: \(error)" }
                loadCalendars()
            }
            .alert("Reopen today?", isPresented: $confirmingReset) {
                Button("Reopen", role: .destructive) { reopenToday() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Today's completions and the points they paid are deleted. Other days are untouched.")
            }
        }
    }

    // MARK: Stage 3 — body and calendar

    private var todayContext: DailyContext? { dailyContexts.first { $0.dayKey == today } }

    private var bodySection: some View {
        Section {
            if let day = todayContext {
                value("Tier", day.tier.rawValue + (day.onCycle ? " (cycle day)" : ""))
                value("Energy / readiness", String(format: "%.3f / %d", day.energy, day.readiness))
                value("HRV", day.hrv.map { String(format: "%.1f ms", $0) } ?? "—")
                value("Sleep", day.sleepHours.map { String(format: "%.2f h", $0) } ?? "—")
                value("Resting HR", day.restingHR.map { String(format: "%.0f bpm", $0) } ?? "—")
            }
            Text(sensorReport).font(.caption).foregroundStyle(.secondary)
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
                    refresh()
                }
            } label: {
                Label("Allow Health access", systemImage: "heart.text.square")
            }
            .disabled(!HealthService.isAvailable)
            if let permissionError {
                Text(permissionError).font(.caption).foregroundStyle(.red)
            }
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
            .disabled(!HealthService.isAvailable)
            if let healthStatus {
                Text(healthStatus).font(.caption).foregroundStyle(.secondary)
            }
            if let previewError {
                Text(previewError).font(.caption).foregroundStyle(.red)
            }
            if let preview { previewRows(preview) }
        } header: {
            Text("Body (today)")
        } footer: {
            Text("The tier is fixed when the day is generated — the first time the app opens that day. Data that syncs later counts from tomorrow. A metric with no data is left out; with none at all the day is normal.")
        }
    }

    /// Read now, not stored: the day's tier stays whatever it was locked at.
    @ViewBuilder
    private func previewRows(_ p: HealthService.Body) -> some View {
        let i = p.inputs
        value("Preview tier", i.tier.rawValue + (i.onCycle ? " (cycle day)" : ""))
        value("Preview energy / readiness", String(format: "%.3f / %d", i.energy, i.readiness))
        value("HRV (baseline)", pair(p.today.hrv, p.baseline.hrv, "%.1f"))
        value("Sleep h (baseline)", pair(p.today.sleepHours, p.baseline.sleepHours, "%.2f"))
        value("Resting HR (baseline)", pair(p.today.restingHR, p.baseline.restingHR, "%.0f"))
        Text("Preview only — not saved. Baseline \"—\" means fewer than \(Energy.minimumDays) days of that metric in the last \(Energy.window).")
            .font(.caption).foregroundStyle(.secondary)
    }

    private func clock() -> String {
        Date().formatted(date: .omitted, time: .standard)
    }

    private func pair(_ today: Double?, _ baseline: Double?, _ format: String) -> String {
        let f = { (v: Double?) in v.map { String(format: format, $0) } ?? "—" }
        return "\(f(today)) (\(f(baseline)))"
    }

    private var workoutSection: some View {
        Section {
            if CalendarService.hasAccess {
                Picker("Calendar", selection: $workoutCalendarID) {
                    Text("None").tag("")
                    ForEach(calendars, id: \.id) { Text($0.title).tag($0.id) }
                }
            } else {
                Button {
                    Task {
                        do { try await CalendarService().requestAccess(); permissionError = nil }
                        catch { permissionError = "Calendar: \(error.localizedDescription)" }
                        loadCalendars()
                    }
                } label: {
                    Label("Allow Calendar access", systemImage: "calendar.badge.checkmark")
                }
            }
            TextField("Title keywords, comma separated", text: $workoutKeywords)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button { refresh() } label: {
                Label("Check for workouts now", systemImage: "arrow.clockwise")
            }
        } header: {
            Text("Workout auto-verify")
        } footer: {
            Text("An event counts only if it is in this calendar and its title contains one of the keywords. Each workout verifies one thing. Also re-checked every time the app comes to the foreground.")
        }
    }

    private func loadCalendars() {
        calendars = CalendarService().calendars()
    }

    private func value(_ name: String, _ text: String) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(text).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func row(_ name: String, _ count: Int, detail: String? = nil) -> some View {
        HStack {
            Text(name)
            Spacer()
            if let detail { Text(detail).foregroundStyle(.secondary) }
            Text("\(count)").monospacedDigit()
        }
    }

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

#Preview {
    DebugView(seedStatus: "Preview", today: Date().dayKey)
        .modelContainer(for: LifeRPGSchema.models, inMemory: true)
}
