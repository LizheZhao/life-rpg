import LifeRPGCore
import SwiftUI

/// Every token, type style, doodle and component in one scroll, for checking light, dark and the
/// largest Dynamic Type at a glance. Reached from Settings later; not part of the app flow.
struct DesignGalleryView: View {
    @State private var demoDone = false
    @State private var demoDots = 6
    @State private var pressed = 0
    @ScaledMetric private var swatchMinimum: CGFloat = 150
    @ScaledMetric private var doodleMinimum: CGFloat = 84

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                section("Colours (light | dark)") { swatches }
                section("Type") { typeStyles }
                section("Text on tiles") { tileText }
                section("Doodles") { doodles }
                section("Pills") { pills }
                section("Complete button") { completeButtons }
                section("Level dots") { dots }
                section("Segmented progress") { segments }
                section("Hand underline") { HandUnderlineText(lead: "let's", emphasis: "level up") }
                section("Cards") { cards }
                section("Avatar") { avatars }
            }
            .padding(.horizontal, LR.Spacing.inset)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(LR.Color.canvas.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Design system").lr(.titleCard).foregroundStyle(LR.Color.ink)
            Text(LRFonts.isActive ? "Custom fonts: Plus Jakarta Sans + Caveat" : "Custom fonts missing, system fallback")
                .lr(.caption)
                .foregroundStyle(LR.Color.inkSecondary)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).lr(.hand).foregroundStyle(LR.Color.inkHand)
            content()
        }
    }

    private var swatches: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: swatchMinimum), spacing: LR.Spacing.gridGap)], spacing: LR.Spacing.gridGap) {
            ForEach(Palette.tokens, id: \.name) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) {
                        Rectangle().fill(LR.Color.color(entry.token)).environment(\.colorScheme, .light)
                        Rectangle().fill(LR.Color.color(entry.token)).environment(\.colorScheme, .dark)
                    }
                    .frame(height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(LR.Color.inkSecondary.opacity(0.4), lineWidth: 0.5))
                    Text(entry.name).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                    Text("\(hex(entry.token.light)) | \(hex(entry.token.dark))")
                        .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                }
            }
        }
    }

    private func hex(_ value: Int) -> String { String(format: "#%06X", value) }

    private var typeStyles: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(LR.Typography.allCases, id: \.self) { style in
                VStack(alignment: .leading, spacing: 2) {
                    Text(sample(style)).lr(style).foregroundStyle(LR.Color.ink)
                    Text(style.name).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                }
            }
        }
    }

    private func sample(_ style: LR.Typography) -> String {
        switch style {
        case .displayGreeting: "Good morning"
        case .displayGreetingEmphasis: "level up"
        case .displayLevel: "8"
        case .titleCard: "Weekly epic"
        case .heading: "Today's quests"
        case .bodyStrong: "Walk 8,000 steps"
        case .caption: "312 coins to level 9"
        case .pill: "5–15"
        case .hand: "day 3 · 4 day streak"
        }
    }

    private var tileText: some View {
        let tints: [(String, Color)] = [("trivial", LR.Color.tintTrivial), ("easy", LR.Color.tintEasy),
                                        ("medium", LR.Color.tintMedium), ("hard", LR.Color.tintHard),
                                        ("hidden", LR.Color.tintHidden)]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: swatchMinimum), spacing: LR.Spacing.gridGap)], spacing: LR.Spacing.gridGap) {
            ForEach(tints, id: \.0) { name, tint in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Walk 8,000 steps").lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                    Text("A view I've recently changed").lr(.caption).foregroundStyle(LR.Color.inkOnTint)
                    PillLabel(text: "\(name) · 12–30", style: .onTint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .lrCard(.tint(tint), radius: LR.Radius.tile)
            }
        }
    }

    private var doodles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: doodleMinimum), spacing: LR.Spacing.gridGap)], spacing: LR.Spacing.gridGap) {
            ForEach(DoodleKey.allCases, id: \.self) { key in
                specimen(key.rawValue) { DoodleView(key: key, size: 56) }
            }
            specimen("check") {
                HandCheck().stroke(LR.Color.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: 40, height: 40)
            }
            specimen("squiggle") {
                Squiggle().stroke(LR.Color.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: 60, height: 9)
            }
        }
    }

    private func specimen<Content: View>(_ name: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 6) {
            content().frame(height: 56)
            Text(name).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .lrCard()
    }

    private var pills: some View {
        FlowRow {
            PillLabel(text: "+15").padding(6).lrCard(.surface, radius: 14)
            PillLabel(text: "Wed · Sat").padding(6).lrCard(.surface, radius: 14)
            PillLabel(text: "overdue · day 2", style: .clay).padding(6).lrCard(.surface, radius: 14)
            PillLabel(text: "auto-verified", style: .onTint).padding(6).lrCard(.tint(LR.Color.tintEasy), radius: 14)
            PillLabel(text: "5–15", style: .onEpic).padding(6).lrCard(.epic, radius: 14)
        }
    }

    private var completeButtons: some View {
        HStack(spacing: 20) {
            labelled("open") { CompleteButton(isDone: false) {} }
            labelled("done") { CompleteButton(isDone: true) {} }
            labelled("tap") { CompleteButton(isDone: demoDone) { demoDone = true } }
            Button("Reset") { demoDone = false }
                .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                .frame(minHeight: 44)
        }
    }

    private var dots: some View {
        VStack(alignment: .leading, spacing: 12) {
            labelled("0") { LevelDotGrid(filled: 0, total: 20) }
            labelled("9") { LevelDotGrid(filled: 9, total: 20) }
            labelled("20") { LevelDotGrid(filled: 20, total: 20) }
            labelled("animated: \(demoDots)") { LevelDotGrid(filled: demoDots, total: 20) }
            HStack(spacing: 20) {
                Button("+3") { demoDots = min(20, demoDots + 3) }
                Button("Reset") { demoDots = 6 }
            }
            .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
            .frame(minHeight: 44)
        }
    }

    private var segments: some View {
        VStack(alignment: .leading, spacing: 10) {
            SegmentedProgress(filled: 3, total: 7)
            SegmentedProgress(filled: 7, total: 7)
            SegmentedProgress(filled: 0, total: 7)
        }
        .padding(16)
        .lrCard(.epic)
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: LR.Spacing.gridGap) {
            Button { pressed += 1 } label: {
                HStack(spacing: 12) {
                    DoodleView(key: .flag, size: 40, tint: LR.Color.onEpic)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ship the side project").lr(.heading).foregroundStyle(LR.Color.onEpic)
                        Text("day 3 of 7 · pressed \(pressed)").lr(.caption).foregroundStyle(LR.Color.epicSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .lrCard(.epic)
            }
            .buttonStyle(PressableCardStyle())
            HStack(spacing: 12) {
                DoodleView(key: .sneaker, size: 40)
                Text("Incline walk, 30 minutes").lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                Spacer(minLength: 0)
                CompleteButton(isDone: false) {}
            }
            .padding(12)
            .lrCard(.surface, radius: LR.Radius.row)
        }
    }

    private var avatars: some View {
        HStack(spacing: 16) {
            AvatarView(size: 44)
            AvatarView(size: 80)
        }
    }

    private func labelled<Content: View>(_ name: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
            Text(name).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
        }
    }
}

/// Wraps its children onto new lines, so pills never truncate at large text sizes.
private struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(bounds.width, subviews)
        for (subview, origin) in zip(subviews, result.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (origins, CGSize(width: maxX, height: y + rowHeight))
    }
}

#Preview("Light") {
    DesignGalleryView().preferredColorScheme(.light)
}

#Preview("Dark") {
    DesignGalleryView().preferredColorScheme(.dark)
}

#Preview("Largest accessibility type") {
    DesignGalleryView().dynamicTypeSize(.accessibility5)
}
