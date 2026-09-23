import LifeRPGCore
import SwiftData
import SwiftUI

/// Owns the day: calls `ensureToday` whenever the app becomes active, so crossing midnight in the
/// background and coming back refreshes the page rather than showing yesterday.
struct RootView: View {
    let seedStatus: String

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var today = Date().dayKey
    @State private var generationError: String?
    /// What the last refresh read from HealthKit and the calendar — shown on the debug page, since
    /// a denied permission otherwise looks exactly like a night with no data.
    @State private var sensorReport = "Not read yet"
    @State private var refreshing = false
    /// A re-read that disagrees with the day already on screen, waiting to be confirmed.
    @State private var replan: Replan.Change?
    @State private var replanInputs: DayInputs?
    @State private var health = HealthService()
    @State private var calendar = CalendarService()
    @AppStorage("workoutCalendarID") private var workoutCalendarID = ""
    @AppStorage("workoutKeywords") private var workoutKeywords = ""
    #if targetEnvironment(simulator)
    // Debug time travel: days added to the real clock. Simulator only — it writes future-dated
    // rows that never go away, which must never happen to the real store on the phone.
    @AppStorage("debugDayOffset") private var dayOffset = 0
    #else
    private let dayOffset = 0
    #endif

    var body: some View {
        TabView {
            TodayView(today: today, generationError: generationError)
                .tabItem { Label("Today", systemImage: "checklist") }
            CalendarView(today: today)
                .tabItem { Label("Calendar", systemImage: "calendar") }
            DebugView(seedStatus: seedStatus, today: today, sensorReport: sensorReport,
                      refresh: { Task { await refresh() } })
                .tabItem { Label("Debug", systemImage: "wrench.and.screwdriver") }
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
        .onChange(of: dayOffset) { Task { await refresh() } }
        .alert("Today's body data changed", isPresented: Binding(
            get: { replan != nil }, set: { if !$0 { replan = nil; replanInputs = nil } }
        ), presenting: replan) { change in
            Button("Re-plan what's open") { apply(change) }
            Button("Leave it", role: .cancel) {}
        } message: { change in
            Text(message(for: change))
        }
    }

    private func message(for change: Replan.Change) -> String {
        var lines = ["Readings now say \(change.toTier.rawValue) rather than \(change.fromTier.rawValue)."]
        if change.keptQuests > 0 {
            lines.append("\(change.keptQuests) finished quest(s) stay exactly as they are.")
        }
        if change.redrawnQuests > 0 {
            lines.append("\(change.redrawnQuests) unfinished slot(s) would be drawn again.")
        }
        if change.adjustedRoutines > 0 {
            lines.append("\(change.adjustedRoutines) open routine(s) would swap to (or back from) a lighter version.")
        }
        return lines.joined(separator: "\n")
    }

    private func apply(_ change: Replan.Change) {
        guard let inputs = replanInputs else { return }
        var rng = SystemRandomNumberGenerator()
        do {
            try Replan.apply(context, on: change.dayKey, inputs: inputs, rng: &rng)
        } catch {
            generationError = "\(error)"
        }
        replan = nil
        replanInputs = nil
    }

    private func refresh() async {
        // Foreground, time travel and the debug button can all land at once; one pass is enough.
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }

        let now = LifeCalendar.gregorian().date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        let todayKey = now.dayKey
        var report: [String] = []

        // Read on every foreground, not only for a day that doesn't exist yet: the watch may not
        // have synced last night's sleep when the app was first opened, and a period logged later
        // in the morning is exactly the case this is for. What the reading does to a day already
        // on screen is asked, never applied silently (`Replan`). Any failure leaves the defaults:
        // a `normal` day, never a blocked one.
        let dayExisted = (try? DayService.dailyContext(for: todayKey, in: context)) != nil
        var inputs = DayInputs()
        // Only a reading that actually came back may re-plan a day: a denied permission returns
        // the `normal` defaults, and those must never read as "your day got easier".
        var readBody = false
        if HealthService.isAvailable {
            do {
                inputs = try await health.inputs(for: todayKey, now: now)
                readBody = true
                report.append("Body: tier \(inputs.tier.rawValue), readiness \(inputs.readiness)"
                              + (inputs.cycleDay.map { ", cycle day \($0)" } ?? ""))
            } catch {
                report.append("Health read failed: \(error.localizedDescription)")
            }
        }

        // Evidence from the last day the app saw through today: catch-up verifies each ended day
        // before judging it. Capped at two weeks — nothing older is still open anyway.
        let floor = DayKey.adding(-14, to: todayKey) ?? todayKey
        let firstKey = max((try? DayService.lastProcessedDayKey(context)) ?? todayKey, floor)
        let from = LifeCalendar.gregorian().startOfDay(for: DayKey.date(min(firstKey, todayKey)) ?? now)
        let events = calendar.events(calendarID: workoutCalendarID, from: from, to: now)
        var mindful: [MindfulSession] = []
        if HealthService.isAvailable {
            do { mindful = try await health.mindfulSessions(from: from, to: now) }
            catch { report.append("Mindful read failed: \(error.localizedDescription)") }
        }
        let filter = WorkoutFilter(calendarID: workoutCalendarID,
                                   keywords: WorkoutFilter.keywords(from: workoutKeywords))
        let evidence = AutoVerify.evidence(events: events, mindful: mindful, filter: filter)
        let todayEvidence = evidence[todayKey] ?? DayEvidence()
        report.append("Today: \(Int(todayEvidence.mindfulMinutes)) mindful min, workouts "
                      + (todayEvidence.workoutMinutes.isEmpty ? "none"
                         : todayEvidence.workoutMinutes.map { "\(Int($0))m" }.joined(separator: ", ")))
        if workoutCalendarID.isEmpty || filter.keywords.isEmpty {
            report.append("Workout filter not set — calendar auto-verify is off")
        }

        var rng = SystemRandomNumberGenerator()
        do {
            // Routine load is not an input: `ensureToday` schedules today's routines and counts them.
            try DayService.ensureToday(context, now: now, inputs: inputs, evidence: evidence, rng: &rng)
            today = todayKey
            generationError = nil
            // The day was already there and the body now says something else: offer to re-plan
            // what is still open. Nothing is changed until it is confirmed.
            if dayExisted, readBody,
               let change = try Replan.preview(context, on: todayKey, inputs: inputs) {
                replan = change
                replanInputs = inputs
            }
        } catch {
            generationError = "\(error)"
        }
        sensorReport = report.joined(separator: "\n")
    }
}
