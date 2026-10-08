import LifeRPGCore
import SwiftUI

/// Settings → Journal: what goes to Apple Journal and when, what "Ask me something" may send to the
/// on-device model, and the one-time Shortcut set-up.
struct JournalSettingsView: View {
    /// The sent log, watched so the status line changes when the Shortcut hands a day over.
    @AppStorage(JournalSentLog.key) private var sentLog = Data()
    @AppStorage(JournalAskSettings.sendWritingKey) private var sendWriting = JournalAskSettings.sendWritingDefault

    var body: some View {
        List {
            Section {
                Text(JournalSentLog.statusLine(JournalSentLog.latest(JournalSentLog.decode(sentLog))))
                    .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                    .frame(minHeight: 44, alignment: .leading)
                Text(Self.explanation)
                    .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                header("Apple Journal")
            }
            .listRowBackground(LR.Color.surface)

            Section {
                Toggle(isOn: $sendWriting) {
                    Text("Send my writing with the question request")
                        .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                }
                .tint(LR.Color.trendDeep)
                .frame(minHeight: 44)
                Text(JournalAskSettings.sendWritingCaption)
                    .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                header("Ask me something")
            }
            .listRowBackground(LR.Color.surface)

            Section {
                Text(Self.steps)
                    .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                header("Set up once")
            }
            .listRowBackground(LR.Color.surface)
        }
        .listRowSeparatorTint(LR.Color.divider)
        .scrollContentBackground(.hidden)
        .background(LR.Color.canvas)
        .reservingTabBarSpace()
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static let explanation = "Apple Journal only lets an app add an entry, never change one. So LifeRPG sends each day once, after it has ended, and nothing goes while you can still edit."

    /// What the user builds once in Shortcuts. Written plainly about what was not tried: neither
    /// the steps on a device nor an automation running unattended has been checked.
    private static let steps = """
        1. In Shortcuts, make a new Shortcut and add Get Journal Text to Send, from LifeRPG.
        2. Add If, and set it to that text has any value.
        3. Inside the If, add Create Journal Entry and give it that text.
        4. In Shortcuts, add a Personal Automation: Time of Day, 5:00 AM, Run Immediately, running that Shortcut.
        5:00 AM is when LifeRPG's day ends. Each day is sent once, as it was at that moment. Changes you make afterwards stay in LifeRPG, and Share is how to send a changed day by hand.
        Not verified: that the automation runs on its own while the phone is locked, and that these steps work as written on your device.
        """

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title).lr(.heading).foregroundStyle(LR.Color.sectionTitle).textCase(nil)
    }
}
