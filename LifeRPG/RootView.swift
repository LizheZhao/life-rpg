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
            DebugView(seedStatus: seedStatus, today: today)
                .tabItem { Label("Debug", systemImage: "wrench.and.screwdriver") }
        }
        .task { refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        .onChange(of: dayOffset) { refresh() }
    }

    private func refresh() {
        let now = LifeCalendar.gregorian().date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        var rng = SystemRandomNumberGenerator()
        do {
            // Tier is still the default `normal` until Stage 3 reads HealthKit. Routine load is
            // not an input: `ensureToday` schedules today's routines and counts them itself.
            try DayService.ensureToday(context, now: now, inputs: DayInputs(), rng: &rng)
            today = now.dayKey
            generationError = nil
        } catch {
            generationError = "\(error)"
        }
    }
}
