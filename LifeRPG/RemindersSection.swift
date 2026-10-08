import LifeRPGCore
import SwiftData
import SwiftUI
import UserNotifications

/// Settings → Reminders: an evening nudge to write and a morning note of what is due. Both are
/// local notifications and both start off; switching one on asks for permission, and a refusal
/// puts the switch back and says where to change it.
struct RemindersSection: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @AppStorage(NotificationService.journalKey) private var journal = false
    @AppStorage(NotificationService.morningKey) private var morning = false
    @AppStorage(NotificationService.morningHourKey) private var morningHour = 8
    @State private var denied = false

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { journal }, set: { switchJournal($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Evening: write about today").lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                    Text("At \(JournalEntryToday.cardStartHour):00, unless you have already written")
                        .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                }
            }
            .tint(LR.Color.trendDeep)
            .frame(minHeight: 44)

            Toggle(isOn: Binding(get: { morning }, set: { switchMorning($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Morning: what is due today").lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                    Text("Says how many routines are due; the quests are drawn when you open the app")
                        .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(LR.Color.trendDeep)
            .frame(minHeight: 44)

            if morning {
                Stepper(value: $morningHour, in: 5...11) {
                    Text("Morning at \(morningHour):00").lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                }
                .frame(minHeight: 44)
                .onChange(of: morningHour) { Task { await NotificationService.reschedule(in: context) } }
            }

            if denied {
                Text("LifeRPG isn't allowed to send notifications. You can change that in iOS Settings.")
                    .lr(.caption).foregroundStyle(LR.Color.clay)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(PillButtonStyle())
            }
        } header: {
            Text("Reminders").lr(.heading).foregroundStyle(LR.Color.sectionTitle).textCase(nil)
        } footer: {
            Text("Reminders are local: nothing leaves your phone. Writing and then leaving the app cancels tonight's.")
                .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textCase(nil)
        }
        .listRowBackground(LR.Color.surface)
        .task { await refreshDenied() }
    }

    private func switchJournal(_ on: Bool) { change(on) { journal = $0 } }
    private func switchMorning(_ on: Bool) { change(on) { morning = $0 } }

    /// Switching off needs no permission. Switching on asks; a refusal leaves the switch off.
    private func change(_ on: Bool, apply: @escaping (Bool) -> Void) {
        guard on else {
            apply(false)
            Task { await NotificationService.reschedule(in: context); await refreshDenied() }
            return
        }
        Task {
            let allowed = await NotificationService.requestAuthorization()
            apply(allowed)
            denied = !allowed
            await NotificationService.reschedule(in: context)
        }
    }

    private func refreshDenied() async {
        denied = await NotificationService.authorization() == .denied && (journal || morning)
    }
}
