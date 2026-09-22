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
    }

    private func refresh() async {
        // Foreground, time travel and the debug button can all land at once; one pass is enough.
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }

        let now = LifeCalendar.gregorian().date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        let todayKey = now.dayKey
        var report: [String] = []

        // The tier is locked when the day is generated, so body data is only read for a day that
        // doesn't exist yet. Any failure leaves the defaults: a `normal` day, never a blocked one.
        var inputs = DayInputs()
        if (try? DayService.dailyContext(for: todayKey, in: context)) == nil, HealthService.isAvailable {
            do {
                inputs = try await health.inputs(for: todayKey, now: now)
                report.append("Body: tier \(inputs.tier.rawValue), readiness \(inputs.readiness)"
                              + (inputs.onCycle ? ", cycle day" : ""))
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
        } catch {
            generationError = "\(error)"
        }
        sensorReport = report.joined(separator: "\n")
    }
}
