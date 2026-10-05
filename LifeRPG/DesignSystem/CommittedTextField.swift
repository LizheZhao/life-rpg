import SwiftUI

/// A single-line setting typed by hand and kept in `UserDefaults` under `key`. The field edits a
/// local draft, so a keystroke touches no storage and no view that reads the stored value. The draft
/// is written when the user is done: return, the keyboard going away (including a button that
/// resigns it first), the page disappearing, or the app leaving the foreground.
struct CommittedTextField: View {
    let title: LocalizedStringKey
    let key: String

    @Environment(\.scenePhase) private var scenePhase
    @State private var draft: String

    init(_ title: LocalizedStringKey, key: String) {
        self.title = title
        self.key = key
        _draft = State(initialValue: UserDefaults.standard.string(forKey: key) ?? "")
    }

    var body: some View {
        TextField(title, text: $draft, prompt: Text(title).foregroundStyle(LR.Color.inkSecondary))
            .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit(commit)
            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidEndEditingNotification)) { _ in
                commit()
            }
            .onDisappear(perform: commit)
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { commit() }
            }
    }

    /// Idempotent, so every path above may call it without checking whether another already did.
    private func commit() {
        guard draft != (UserDefaults.standard.string(forKey: key) ?? "") else { return }
        UserDefaults.standard.set(draft, forKey: key)
    }
}

/// Resigns whatever text field is editing, which commits a `CommittedTextField` before the caller
/// reads its value from `UserDefaults`.
@MainActor func endEditing() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
