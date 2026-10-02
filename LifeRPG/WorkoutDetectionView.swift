import EventKit
import LifeRPGCore
import SwiftUI

/// Which calendars are read for workouts, and the words a title must contain (`PLAN.md` §5).
/// Pushed from Settings. The two settings are stored under the keys `RootView` reads on every
/// refresh, so a change here is picked up the next time the app comes to the foreground, or at
/// once through "Check for workouts now".
struct WorkoutDetectionView: View {
    /// The last check `RootView` ran, from a foreground or from the button.
    let check: WorkoutCheck?
    let refresh: () async -> Void

    @AppStorage("workoutCalendarID") private var calendarSetting = ""
    @AppStorage("workoutKeywords") private var keywords = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorization = CalendarService.authorization
    @State private var calendars: [CalendarService.Info] = []
    @State private var requestError: String?
    @State private var checking = false

    private var selection: CalendarSelection { CalendarSelection(setting: calendarSetting) }

    var body: some View {
        List {
            accessSection
            if authorization == .fullAccess {
                calendarsSection
            }
            keywordsSection
            Section {
                Button { Task { await runCheck() } } label: {
                    HStack {
                        label("Check for workouts now", systemImage: "arrow.clockwise")
                        Spacer()
                        if checking { ProgressView() }
                    }
                }
                .disabled(checking)
            } footer: {
                footer("Each workout verifies one thing. Also checked every time the app comes to the foreground.")
            }
            .listRowBackground(LR.Color.surface)
            if let check {
                Section {
                    CheckResultCard(check: check)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    header("Last check")
                }
            }
        }
        .listRowSeparatorTint(LR.Color.divider)
        .scrollContentBackground(.hidden)
        .background(LR.Color.canvas)
        .reservingTabBarSpace()
        .navigationTitle("Workout detection")
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reload() }
        }
        .onChange(of: check) { _, new in
            guard checking, let new else { return }
            if new.verified.isEmpty { Haptics.selection() } else { Haptics.notify(.success) }
        }
    }

    private func runCheck() async {
        checking = true
        await refresh()
        checking = false
    }

    private var accessSection: some View {
        Section {
            HStack {
                label("Calendar access", systemImage: "calendar")
                Spacer()
                Text(accessText)
                    .lr(.caption)
                    .foregroundStyle(LR.Color.inkSecondary)
            }
            .frame(minHeight: 44)
            if authorization != .fullAccess {
                Button(action: allowOrOpenSettings) {
                    label(authorization == .notDetermined ? "Allow Calendar access" : "Open iOS Settings",
                          systemImage: "calendar.badge.checkmark")
                }
            }
            if let requestError {
                Text(requestError).lr(.caption).foregroundStyle(LR.Color.clay)
            }
        } header: {
            header("Access")
        }
        .listRowBackground(LR.Color.surface)
    }

    private var calendarsSection: some View {
        Section {
            Toggle(isOn: allCalendars) {
                label("All calendars", systemImage: "calendar.day.timeline.left")
            }
            .frame(minHeight: 44)
            if selection != .all {
                ForEach(calendars) { calendar in
                    Button { calendarSetting = selection.toggling(calendar.id).setting } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(calendar.title).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                                if !calendar.source.isEmpty {
                                    Text(calendar.source).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                                }
                            }
                            Spacer()
                            if selection.contains(calendar.id) {
                                Image(systemName: "checkmark").foregroundStyle(LR.Color.ink)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(selection.contains(calendar.id) ? .isSelected : [])
                }
            }
        } header: {
            header("Calendars")
        } footer: {
            footer(selection == .all
                   ? "Every calendar is read. Only events whose title contains a keyword count."
                   : "Only the checked calendars are read.")
        }
        .listRowBackground(LR.Color.surface)
    }

    private var keywordsSection: some View {
        Section {
            TextField("Title keywords, comma separated", text: $keywords,
                      prompt: Text("Title keywords, comma separated").foregroundStyle(LR.Color.inkSecondary))
                .lr(.bodyStrong)
                .foregroundStyle(LR.Color.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 44)
        } header: {
            header("Keywords")
        } footer: {
            footer("An event counts only if its title contains one of these keywords, so meetings do not count. All-day events never count. With no keywords, nothing is detected.")
        }
        .listRowBackground(LR.Color.surface)
    }

    private var allCalendars: Binding<Bool> {
        Binding(get: { selection == .all },
                set: { calendarSetting = ($0 ? CalendarSelection.all : .none).setting })
    }

    private var accessText: LocalizedStringKey {
        switch authorization {
        case .fullAccess: "Allowed"
        case .notDetermined: "Not asked yet"
        case .writeOnly: "Write only"
        default: "Denied"
        }
    }

    private func reload() {
        authorization = CalendarService.authorization
        calendars = CalendarService().calendars()
    }

    private func allowOrOpenSettings() {
        if authorization == .notDetermined {
            Task {
                do { try await CalendarService().requestAccess(); requestError = nil }
                catch { requestError = "Calendar: \(error.localizedDescription)" }
                reload()
            }
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func label(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .lr(.bodyStrong)
            .foregroundStyle(LR.Color.ink)
    }

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .lr(.heading)
            .foregroundStyle(LR.Color.inkSecondary)
            .textCase(nil)
    }

    private func footer(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .lr(.caption)
            .foregroundStyle(LR.Color.inkSecondary)
    }
}

/// What the last check read and found, in plain words. All wording that depends on the outcome
/// lives here; which outcome it was is `WorkoutCheck`'s call.
private struct CheckResultCard: View {
    let check: WorkoutCheck

    private var verifiedSome: Bool { !check.verified.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: verifiedSome ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(verifiedSome ? LR.Color.ink : LR.Color.inkSecondary)
                Text(title).lr(.heading).foregroundStyle(LR.Color.ink)
                Spacer(minLength: 8)
                Text("Checked \(check.checkedAt.formatted(date: .omitted, time: .shortened))")
                    .lr(.caption).monospacedDigit().foregroundStyle(LR.Color.inkSecondary)
            }
            if verifiedSome {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(check.verified.enumerated()), id: \.offset) { _, title in
                        Text(title).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                    }
                }
            }
            Text(reason).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
            Rectangle().fill(LR.Color.divider).frame(height: 1)
            fact("Calendar events read", "\(check.eventsRead) since \(check.windowStart.formatted(.dateTime.month().day()))")
            fact("Matched a keyword", "\(check.matched)")
            fact("Workouts today", check.workoutMinutes.isEmpty
                 ? "None" : check.workoutMinutes.map { "\($0) min" }.joined(separator: ", "))
            fact("Mindful today", "\(check.mindfulMinutes) min")
            if !check.unmatched.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Did not match").lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                    ForEach(Array(check.unmatched.enumerated()), id: \.offset) { _, event in
                        Text(event.isAllDay ? "\(event.title) (all-day, never counts)" : event.title)
                            .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard(.surface, radius: LR.Radius.row)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func fact(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
            Spacer(minLength: 8)
            Text(value).lr(.bodyStrong).monospacedDigit().foregroundStyle(LR.Color.ink)
        }
    }

    private var title: LocalizedStringKey {
        if verifiedSome { return "Verified just now" }
        return check.outcome == .matched ? "Nothing new verified" : "Nothing detected"
    }

    private var reason: LocalizedStringKey {
        switch check.outcome {
        case .noCalendarAccess:
            "Calendar access is off, so no events could be read. Allow it under Access."
        case .noCalendarsSelected:
            "No calendar is selected. Turn on All calendars or check at least one."
        case .noKeywords:
            "No keywords are set. An event only counts when its title contains one."
        case .noEventsInWindow:
            "The selected calendars have no events in this window."
        case .noneMatched:
            "Events were found, but none has a keyword in its title or sits in a selected calendar."
        case .matched:
            verifiedSome
                ? "Each workout verifies one open item whose rule it satisfies."
                : "Matching events were found, but no open quest or routine took them. A workout must be long enough for an item's rule and fall on its day."
        }
    }
}

#Preview {
    NavigationStack { WorkoutDetectionView(check: nil, refresh: {}) }
}
