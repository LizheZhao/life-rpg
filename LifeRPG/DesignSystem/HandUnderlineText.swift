import SwiftUI

/// A light line with one ExtraBold word under a hand-drawn squiggle that draws itself on once.
/// The squiggle hangs off the emphasis word's own frame, so it follows any font size.
struct HandUnderlineText: View {
    let lead: String
    let emphasis: String

    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var squiggleHeight: CGFloat = 9

    var body: some View {
        // At large text sizes the pair no longer fits on one line, and wrapping an underlined
        // word mid-way would split its squiggle; stack them instead.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) { leadText; emphasisText }
            VStack(alignment: .leading, spacing: 0) { leadText; emphasisText }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(lead) \(emphasis)")
        .onAppear { drawn = true }
    }

    private var leadText: some View {
        Text(lead).lr(.displayGreeting).foregroundStyle(LR.Color.ink)
    }

    private var emphasisText: some View {
        Text(emphasis)
            .lr(.displayGreetingEmphasis)
            .foregroundStyle(LR.Color.ink)
            .fixedSize()
            .overlay(alignment: .bottom) {
                Squiggle()
                    .trim(from: 0, to: drawn || reduceMotion ? 1 : 0)
                    .stroke(LR.Color.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(height: squiggleHeight)
                    .opacity(drawn || !reduceMotion ? 1 : 0)
                    .offset(y: squiggleHeight * 0.6)
                    .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.6).delay(0.15), value: drawn)
            }
            .padding(.bottom, squiggleHeight * 0.6)
    }
}
