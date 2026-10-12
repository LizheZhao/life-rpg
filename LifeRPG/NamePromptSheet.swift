import LifeRPGCore
import SwiftUI

/// Where the name lives: in `UserDefaults`, not the store; the JSON backup carries it. It is only
/// ever shown back to the person (the greeting, Settings).
enum ProfileKeys {
    static let name = "profile.name"
    /// Set once the question has been asked (answered or skipped), so it is asked once.
    static let asked = "profile.asked"
}

/// "What should we call you?": asked once when the first-launch intro was skipped (a store that
/// already had history) and no name was given, and reachable again from Settings.
struct NamePromptSheet: View {
    var title = "What should we call you?"
    var caption: String?

    @AppStorage(ProfileKeys.name) private var storedName = ""
    @AppStorage(ProfileKeys.asked) private var asked = false
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).lr(.heading).foregroundStyle(LR.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let caption {
                Text(caption).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField("Your name", text: $text, prompt: Text("Your name").foregroundStyle(LR.Color.inkSecondary))
                .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)
                .onSubmit(save)
                .frame(minHeight: 44)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lrCard(.surface, radius: LR.Radius.row)
            Spacer(minLength: 0)
            ConfirmBar(title: "Continue", enabled: UserProfile.cleanName(text) != nil, action: save)
            Button(storedName.isEmpty ? "Skip" : "Not now") { finish() }
                .lr(.bodyStrong).foregroundStyle(LR.Color.inkSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .background(LR.Color.canvas.ignoresSafeArea())
        .presentationDetents([.medium])
        .onAppear { text = storedName; focused = true }
        .onDisappear { asked = true }
    }

    private func save() {
        guard let name = UserProfile.cleanName(text) else { return }
        storedName = name
        finish()
    }

    private func finish() {
        asked = true
        dismiss()
    }
}
