import LifeRPGCore
import SwiftUI

/// The bar above the keyboard: the "Ask me something" pill, a `Questions` menu holding the fixed
/// questions, and the word count at the right. A question already in the entry is dimmed in the
/// menu and does nothing (Core's `insertingPrompt` refuses it as well). `leading` holds the pill and
/// its divider.
struct JournalPromptBar<Leading: View>: View {
    let model: JournalEditorModel
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 8) {
            leading
            questionsMenu
            Spacer(minLength: 4)
            Text(model.wordCountText).lr(.caption)
                .foregroundStyle(LR.Color.inkSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.trailing, 20)
                .padding(.leading, 4)
        }
        .padding(.leading, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(LR.Color.surface)
        .overlay(alignment: .top) { Rectangle().fill(LR.Color.hairline).frame(height: 1) }
    }

    private var questionsMenu: some View {
        Menu {
            ForEach(JournalFixedKey.allCases, id: \.self) { key in
                let used = model.isUsed(key)
                Button {
                    guard !used else { return }
                    Haptics.selection()
                    model.insert(key)
                } label: {
                    if used {
                        Label(key.chipLabel(language: model.language), systemImage: "checkmark")
                    } else {
                        Text(key.chipLabel(language: model.language))
                    }
                }
                .disabled(used)
            }
        } label: {
            HStack(spacing: 6) {
                Text("Questions").lr(.chipLabel).lineLimit(1)
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(LR.Color.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .background(Capsule().fill(LR.Color.canvas))
            .overlay(Capsule().strokeBorder(LR.Color.dotEmpty, lineWidth: 1))
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .fixedSize()
        .accessibilityLabel("Questions")
        .accessibilityHint("Pick a question to add at the cursor")
    }
}
