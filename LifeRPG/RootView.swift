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

    var body: some View {
        TabView {
            TodayView(today: today, generationError: generationError)
                .tabItem { Label("Today", systemImage: "checklist") }
            DebugView(seedStatus: seedStatus)
                .tabItem { Label("Debug", systemImage: "wrench.and.screwdriver") }
        }
        .task { refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
    }

    private func refresh() {
        let now = Date()
        var rng = SystemRandomNumberGenerator()
        do {
            // Stage 1 inputs are the defaults: tier `normal`, no routine load. Stage 2 fills the
            // load from the frequency scheduler, Stage 3 the tier from HealthKit.
            try DayService.ensureToday(context, now: now, inputs: DayInputs(), rng: &rng)
            today = now.dayKey
            generationError = nil
        } catch {
            generationError = "\(error)"
        }
    }
}
