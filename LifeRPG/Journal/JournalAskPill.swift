import LifeRPGCore
import SwiftUI

/// "Ask me something": the dark pill at the left of the prompt bar, with its divider. The sparkle
/// becomes a spinner while the request is out. At five model prompts it is dimmed and does nothing,
/// and the bar says why (`JournalAskCappedHint`).
struct JournalAskPill: View {
    let model: JournalEditorModel

    var body: some View {
        let capped = model.askIsCapped
        HStack(spacing: 8) {
            Button {
                guard !capped else { return }
                Haptics.selection()
                model.ask()
            } label: {
                HStack(spacing: 6) {
                    ZStack {
                        if model.asking {
                            ProgressView().controlSize(.mini).tint(LR.Color.promptRule)
                        } else {
                            Image(systemName: "sparkle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(LR.Color.promptRule)
                        }
                    }
                    .frame(width: 15, height: 15)
                    Text("Ask me something").lr(.bodyStrong).foregroundStyle(LR.Color.onNight)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
                .background(Capsule().fill(LR.Color.nightCard))
                .opacity(capped ? 0.4 : 1)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel("Ask me something")
            .accessibilityValue(model.asking ? "Asking" : "")
            .accessibilityHint(capped ? model.cappedTooltip : "Adds a question about your day at the cursor")
            Rectangle().fill(LR.Color.hairline).frame(width: 1, height: 22)
        }
    }
}

/// The dimmed pill's tooltip as a line under the bar's chips, since a touch screen has no hover.
struct JournalAskCappedHint: View {
    let model: JournalEditorModel

    var body: some View {
        if model.askIsCapped {
            Text(model.cappedTooltip).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(LR.Color.surface)
        }
    }
}

/// What follows a tap besides the prompt: a toast that fades, or the safety line in a quiet card the
/// reader dismisses. It sits above the bar, so the keyboard and the cursor are not touched.
struct JournalAskNoticeView: View {
    let model: JournalEditorModel

    var body: some View {
        if let notice = model.notice {
            Group {
                switch notice.value {
                case .toast(let text):
                    Text(text).lr(.caption).foregroundStyle(LR.Color.onNight)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(LR.Color.nightCard))
                        .accessibilityAddTraits(.updatesFrequently)
                case .safety(let line):
                    VStack(alignment: .leading, spacing: 10) {
                        Text(line).lr(.caption).foregroundStyle(LR.Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Got it") { model.dismissNotice() }
                            .lr(.bodyStrong).foregroundStyle(LR.Color.trendDeep)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 20).fill(LR.Color.surface)
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 2))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .id(notice.serial)
            .transition(.opacity)
        }
    }
}
