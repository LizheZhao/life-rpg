import LifeRPGCore
import SwiftUI

/// The payout reveal: the number shakes side to side through a few throwaway values, then lands.
///
/// **Nothing here decides anything.** The points were rolled inside `Completion.complete` and
/// written to the ledger before this view existed; `Scoring.Breakdown` only describes that result.
/// The numbers flashing past during the shake are discarded frames drawn from the same range — an
/// animation that rolled its own number would be showing you something other than what you were
/// paid, and re-rolling until the number is good is exactly what `PLAN.md` §3's "completion is
/// final" exists to prevent.
struct PointsRollView: View {
    let title: String
    let slotLabel: String
    let breakdown: Scoring.Breakdown
    /// Called with the rating you picked, or nil if you dismissed without one. Rating is always
    /// optional: this card appears several times a day, and a reward screen that demands an answer
    /// before it goes away turns into a toll booth.
    let onDismiss: (Int?) -> Void

    @State private var shift: CGFloat = 0
    @State private var shown = 0
    @State private var landed = false
    @State private var bonusRevealed = false
    @State private var askingForRating = false
    @State private var picked: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var total: Int { bonusRevealed ? breakdown.awarded : shown }

    var body: some View {
        ZStack {
            // Tapping anywhere skips the rest — this plays several times a day, every day, and a
            // reveal you cannot cut short stops being a reward quite quickly.
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss(picked) }

            card
                .padding(.horizontal, 40)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        .task { await run() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(breakdown.awarded) points")
        .accessibilityAddTraits(.isModal)
    }

    private var card: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(slotLabel).font(.caption2.bold())
                    if breakdown.payoutRange.lowerBound != breakdown.payoutRange.upperBound {
                        Text("\(breakdown.payoutRange.lowerBound)–\(breakdown.payoutRange.upperBound)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("+\(total)")
                    .font(.system(size: 58, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(landed ? .green : .primary)
                    .contentTransition(.numericText())
                    .offset(x: shift)
                if bonusRevealed, breakdown.bonus > 0 {
                    Text("★ +\(breakdown.bonus)")
                        .font(.footnote.bold())
                        .foregroundStyle(.orange)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            // A fixed height so the card doesn't breathe as the digit count changes mid-shake.
            .frame(height: 70)

            if let note {
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }

            if askingForRating {
                Divider()
                rating.transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
        .shadow(radius: 24, y: 8)
    }

    /// Only says something when there is something to say: the T group didn't roll, and a low-tier
    /// day paid more than the band would suggest.
    private var note: String? {
        if !breakdown.isRolled { return "the group scores \(breakdown.rolled) as a whole — not a roll" }
        if breakdown.multiplier > 1 { return String(format: "×%.1f low energy", breakdown.multiplier) }
        return nil
    }

    // MARK: rating

    /// Asked here rather than on a separate screen because this is the one moment the answer is
    /// cheap and honest — you have just done the thing. `QuestRating` keeps every answer with its
    /// date, so changing your mind later is a new row, not an overwrite.
    private static let scale: [(value: Int, symbol: String, label: String)] = [
        (-2, "hand.thumbsdown.fill", "Hated it"),
        (-1, "hand.thumbsdown", "Rather not"),
        (0, "minus", "Fine"),
        (1, "hand.thumbsup", "Liked it"),
        (2, "hand.thumbsup.fill", "Loved it"),
    ]

    private var rating: some View {
        VStack(spacing: 8) {
            Text(picked.flatMap { value in Self.scale.first { $0.value == value }?.label }
                 ?? "How did that feel?")
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)

            HStack(spacing: 10) {
                ForEach(Self.scale, id: \.value) { step in
                    Button {
                        withAnimation(.snappy) { picked = step.value }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task {
                            try? await Task.sleep(for: .milliseconds(320))
                            onDismiss(step.value)
                        }
                    } label: {
                        Image(systemName: step.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 42, height: 34)
                            .background(picked == step.value ? AnyShapeStyle(.tint)
                                                             : AnyShapeStyle(.quaternary),
                                        in: RoundedRectangle(cornerRadius: 9))
                            .foregroundStyle(picked == step.value ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(step.label)
                }
            }
        }
    }

    // MARK: the sequence

    /// Decaying side-to-side swings. The last one is 0, so it settles centred without a separate
    /// correction step.
    private static let swings: [CGFloat] = [-26, 20, -15, 11, -6, 0]

    private func run() async {
        if reduceMotion {
            shown = breakdown.rolled
            landed = true
            bonusRevealed = true
            askingForRating = true
            await waitThenDismiss()
            return
        }

        for (step, x) in Self.swings.enumerated() {
            withAnimation(.easeInOut(duration: 0.1)) { shift = x }
            // The T group has nothing to roll, so the digits don't pretend to — it just moves.
            if breakdown.isRolled {
                shown = Int.random(in: breakdown.range)
            }
            try? await Task.sleep(for: .milliseconds(88 + step * 14))
        }

        withAnimation(.snappy) {
            shown = breakdown.rolled
            landed = true
        }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

        if breakdown.bonus > 0 {
            try? await Task.sleep(for: .milliseconds(340))
            withAnimation(.bouncy) { bonusRevealed = true }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } else {
            bonusRevealed = true
        }

        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(.snappy) { askingForRating = true }
        await waitThenDismiss()
    }

    /// The card no longer closes itself the moment the number lands — there is a question on it
    /// now. It still closes on its own eventually, so a card left open on a phone put down
    /// mid-tap doesn't sit there until the app is force-quit.
    private func waitThenDismiss() async {
        try? await Task.sleep(for: .seconds(8))
        if picked == nil { onDismiss(nil) }
    }
}

#Preview("hard roll") {
    PointsRollView(title: "Read a paper and write a summary", slotLabel: "H",
                   breakdown: Scoring.breakdown(slot: .hard, isTrivialGroup: false,
                                                isHidden: false, tier: .normal, awarded: 37),
                   onDismiss: { _ in })
}

#Preview("hidden, low energy") {
    PointsRollView(title: "Visit a coffee shop you've never been to", slotLabel: "★",
                   breakdown: Scoring.breakdown(slot: .medium, isTrivialGroup: false,
                                                isHidden: true, tier: .low, awarded: 37),
                   onDismiss: { _ in })
}

#Preview("trivial group") {
    PointsRollView(title: "Floss · Listen to an old song · Use eye drops", slotLabel: "T×3",
                   breakdown: Scoring.breakdown(slot: .easy, isTrivialGroup: true,
                                                isHidden: false, tier: .normal, awarded: 12),
                   onDismiss: { _ in })
}
