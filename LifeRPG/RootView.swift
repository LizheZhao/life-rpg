import LifeRPGCore
import SwiftData
import SwiftUI

/// Owns the day: calls `ensureToday` whenever the app becomes active, so crossing midnight in the
/// background and coming back refreshes the page rather than showing yesterday.
struct RootView: View {
    let seedStatus: String

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = RootTab.today
    @AppStorage(ProfileKeys.asked) private var askedName = false
    @State private var askingName = false
    @AppStorage(OnboardingKeys.done) private var introDone = false
    @State private var showingIntro = false
    /// Set by Today, Rewards and Settings while their card is up, so the bar fades out under the dim.
    @State private var tabBarHidden = false
    @State private var today = Date().dayKey
    @State private var generationError: String?
    /// What the last refresh read from HealthKit and the calendar — shown on the debug page, since
    /// a denied permission otherwise looks exactly like a night with no data.
    @State private var sensorReport = "Not read yet"
    @State private var refreshing = false
    /// What the last refresh found for workouts — the result card on the Workout detection page.
    @State private var workoutCheck: WorkoutCheck?
    /// A re-read that disagrees with the day already on screen, waiting to be confirmed.
    @State private var replan: Replan.Change?
    @State private var replanInputs: DayInputs?
    @State private var health = HealthService()
    @State private var calendar = CalendarService()
    #if targetEnvironment(simulator)
    // Debug time travel: days added to the real clock. Simulator only — it writes future-dated
    // rows that never go away, which must never happen to the real store on the phone.
    @AppStorage("debugDayOffset") private var dayOffset = 0
    #else
    private let dayOffset = 0
    #endif

    var body: some View {
        TabView(selection: $tab) {
            TodayView(today: today, generationError: generationError, hidesTabBar: $tabBarHidden)
                .toolbar(.hidden, for: .tabBar)
                .tag(RootTab.today)
            CalendarView(today: today)
                .toolbar(.hidden, for: .tabBar)
                .tag(RootTab.calendar)
            TrendsView(today: today)
                .toolbar(.hidden, for: .tabBar)
                .tag(RootTab.trends)
            RewardsView(today: today, hidesTabBar: $tabBarHidden)
                .toolbar(.hidden, for: .tabBar)
                .tag(RootTab.rewards)
            SettingsView(seedStatus: seedStatus, today: today, sensorReport: sensorReport,
                         check: workoutCheck,
                         refresh: { await refresh(waitIfBusy: true) },
                         onImported: { Task { await refresh(); await NotificationService.reschedule(in: context) } },
                         hidesTabBar: $tabBarHidden,
                         showIntro: { showingIntro = true })
                .toolbar(.hidden, for: .tabBar)
                .tag(RootTab.settings)
        }
        .overlay(alignment: .bottom) { FloatingTabBar(selection: $tab, hidden: tabBarHidden) }
        .task {
            // The intro comes before the first draw, so a Health connection made there already
            // shapes today. A store with history (a restore, a phone in use) never shows it.
            if needsIntro() { showingIntro = true } else { await start() }
        }
        .sheet(isPresented: $askingName) { NamePromptSheet() }
        .fullScreenCover(isPresented: $showingIntro, onDismiss: { Task { await start() } }) {
            OnboardingView {
                introDone = true
                askedName = true
                showingIntro = false
            }
        }
        // Erasing every record clears the flag: the intro comes back at once.
        .onChange(of: introDone) { _, done in if !done, needsIntro() { showingIntro = true } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !showingIntro { Task { await refresh() } }
            // Leaving is when "I wrote today" has to take effect; coming back picks up a new day.
            if phase == .active || phase == .background { Task { await NotificationService.reschedule(in: context) } }
        }
        .onChange(of: dayOffset) { Task { await refresh() } }
        .alert(replan.map { $0.toRecovery != $0.fromRecovery } == true ? "Recovery" : "Today's body data changed",
               isPresented: Binding(
            get: { replan != nil }, set: { if !$0 { replan = nil; replanInputs = nil } }
        ), presenting: replan) { change in
            Button("Re-plan what's open") { apply(change) }
            Button("Leave it", role: .cancel) {}
        } message: { change in
            Text(message(for: change))
        }
    }

    /// Whether the intro is due; a store that already has history marks it seen instead.
    private func needsIntro() -> Bool {
        guard !introDone else { return false }
        if (try? Onboarding.shouldShow(introDone: false, in: context)) ?? false { return true }
        introDone = true
        return false
    }

    private func start() async {
        await refresh()
        await NotificationService.reschedule(in: context)
        if !askedName { askingName = true }
    }

    private func message(for change: Replan.Change) -> String {
        var lines = change.toRecovery != change.fromRecovery
            ? [change.toRecovery ? "Recovery starts today: only trivial and easy quests, and nothing is charged."
                                 : "Recovery is over: today goes back to what your readings say."]
            : ["Readings now say \(change.toTier.rawValue) rather than \(change.fromTier.rawValue)."]
        if change.keptQuests > 0 {
            lines.append("\(change.keptQuests) quest(s) stay as they are — everything finished, and anything open the new day still asks for.")
        }
        if change.droppedQuests > 0 {
            lines.append("\(change.droppedQuests) open slot(s) the new day no longer has would be dropped.")
        }
        if change.newQuests > 0 {
            lines.append("\(change.newQuests) new slot(s) would be drawn.")
        }
        if change.adjustedRoutines > 0 {
            lines.append("\(change.adjustedRoutines) open routine(s) would swap to (or back from) a lighter version.")
        }
        if change.restedRoutines > 0 {
            lines.append("\(change.restedRoutines) routine(s) too heavy for now would be set aside, without a charge.")
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

    /// `waitIfBusy` is for a tap that must show a result: it runs after the pass in flight, which
    /// may have read the settings before they changed. Automatic callers just skip.
    private func refresh(waitIfBusy: Bool = false) async {
        // Foreground, time travel and the debug button can all land at once; one pass is enough.
        while waitIfBusy && refreshing { try? await Task.sleep(for: .milliseconds(100)) }
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
        let defaults = UserDefaults.standard
        let selection = CalendarSelection(setting: defaults.string(forKey: WorkoutSettings.calendarKey) ?? "")
        let events = calendar.events(selection: selection, from: from, to: now)
        var mindful: [MindfulSession] = []
        if HealthService.isAvailable {
            do { mindful = try await health.mindfulSessions(from: from, to: now) }
            catch { report.append("Mindful read failed: \(error.localizedDescription)") }
        }
        let filter = WorkoutFilter(calendars: selection,
                                   keywords: WorkoutFilter.keywords(from: defaults.string(forKey: WorkoutSettings.keywordsKey) ?? ""))
        let evidence = AutoVerify.evidence(events: events, mindful: mindful, filter: filter)
        let todayEvidence = evidence[todayKey] ?? DayEvidence()
        report.append("Today: \(Int(todayEvidence.mindfulMinutes)) mindful min, workouts "
                      + (todayEvidence.workoutMinutes.isEmpty ? "none"
                         : todayEvidence.workoutMinutes.map { "\(Int($0))m" }.joined(separator: ", ")))
        if selection == .none || filter.keywords.isEmpty {
            report.append("Workout filter not set — calendar auto-verify is off")
        }

        inputs = Recovery.applied(RecoveryKeys.period(), to: inputs, on: todayKey)
        let recoveryMoved = (try? DayService.dailyContext(for: todayKey, in: context))?.isRecovery
            != inputs.isRecovery(todayKey)

        let verifiedBefore = (try? AutoVerify.verifiedItems(on: todayKey, in: context)) ?? []
        var rng = SystemRandomNumberGenerator()
        do {
            // Routine load is not an input: `ensureToday` schedules today's routines and counts them.
            try DayService.ensureToday(context, now: now, inputs: inputs, evidence: evidence, rng: &rng)
            today = todayKey
            generationError = nil
            // The day was already there and the body now says something else: offer to re-plan
            // what is still open. Nothing is changed until it is confirmed.
            // Turning recovery on or off is the user's own word, so it re-plans with or without a reading.
            if dayExisted, readBody || recoveryMoved,
               let change = try Replan.preview(context, on: todayKey, inputs: inputs) {
                replan = change
                replanInputs = inputs
            }
        } catch {
            generationError = "\(error)"
        }
        let verifiedAfter = (try? AutoVerify.verifiedItems(on: todayKey, in: context)) ?? []
        workoutCheck = WorkoutCheck.make(checkedAt: Date(), windowStart: from,
                                         calendarAccess: CalendarService.hasAccess, filter: filter,
                                         events: events, todayEvidence: todayEvidence,
                                         before: verifiedBefore, after: verifiedAfter)
        sensorReport = report.joined(separator: "\n")
    }
}
