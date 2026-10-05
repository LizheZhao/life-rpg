import LifeRPGCore
import SwiftUI

/// The bar above the keyboard: the fixed chips, scrolling sideways, and the word count at the
/// right. A chip whose prompt is already in the entry is dimmed and does nothing (Core's
/// `insertingPrompt` refuses it as well). `leading` holds the "Ask me something" pill and its
/// divider, which stay put while the chips scroll beside them.
struct JournalPromptBar<Leading: View>: View {
    let model: JournalEditorModel
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 8) {
            leading
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(JournalFixedKey.allCases, id: \.self) { key in chip(key) }
                }
            }
            Text(model.wordCountText).lr(.caption)
                .foregroundStyle(LR.Color.inkSecondary)
                .monospacedDigit()
                .fixedSize()
                .padding(.trailing, 20)
                .padding(.leading, 4)
        }
        .padding(.leading, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(LR.Color.surface)
        .overlay(alignment: .top) { Rectangle().fill(LR.Color.hairline).frame(height: 1) }
    }

    private func chip(_ key: JournalFixedKey) -> some View {
        let used = model.isUsed(key)
        let label = key.chipLabel(language: model.language)
        return Button {
            guard !used else { return }
            Haptics.selection()
            model.insert(key)
        } label: {
            Text(label).lr(.chipLabel).foregroundStyle(LR.Color.ink)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
                .background(Capsule().fill(LR.Color.canvas))
                .overlay(Capsule().strokeBorder(LR.Color.dotEmpty, lineWidth: 1))
                .opacity(used ? 0.4 : 1)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(used ? "Already in this entry" : "Adds this question at the cursor")
    }
}
