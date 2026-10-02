import EventKit
import LifeRPGCore
import SwiftUI

/// Which calendars are read for workouts, and the words a title must contain (`PLAN.md` §5).
/// Pushed from Settings. The two settings are stored under the keys `RootView` reads on every
/// refresh, so a change here is picked up the next time the app comes to the foreground, or at
/// once through "Check for workouts now".
struct WorkoutDetectionView: View {
    let refresh: () -> Void

    @AppStorage("workoutCalendarID") private var calendarSetting = ""
    @AppStorage("workoutKeywords") private var keywords = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorization = CalendarService.authorization
    @State private var calendars: [CalendarService.Info] = []
    @State private var requestError: String?

    private var selection: CalendarSelection { CalendarSelection(setting: calendarSetting) }

    var body: some View {
        List {
            accessSection
            if authorization == .fullAccess {
                calendarsSection
            }
            keywordsSection
            Section {
                Button { refresh() } label: {
                    label("Check for workouts now", systemImage: "arrow.clockwise")
                }
            } footer: {
                footer("Each workout verifies one thing. Also checked every time the app comes to the foreground.")
            }
            .listRowBackground(LR.Color.surface)
        }
        .scrollContentBackground(.hidden)
        .background(LR.Color.canvas)
        .navigationTitle("Workout detection")
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reload() }
        }
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
            TextField("Title keywords, comma separated", text: $keywords)
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

#Preview {
    NavigationStack { WorkoutDetectionView(refresh: {}) }
}
