import LifeRPGCore
import SwiftUI

// The Today page's cards. Each takes a plain state built in Core and closures, and owns no data:
// what a tap does (the confirmation, a purchase) is decided by `TodayView`.

extension QuestTint {
    var color: Color {
        switch self {
        case .trivial: LR.Color.tintTrivial
        case .easy: LR.Color.tintEasy
        case .medium: LR.Color.tintMedium
        case .hard: LR.Color.tintHard
        case .hidden: LR.Color.tintHidden
        case .routine: LR.Color.tintRoutine
        case .epic: LR.Color.tintEpic
        }
    }
}

/// `+20`, `Wed · Sat`, `overdue · day 2`, wrapped so none of them truncates.
private struct PillRow: View {
    let pills: [PillState]
    var onTint = false

    var body: some View {
        FlowRow(spacing: 6) {
            ForEach(Array(pills.enumerated()), id: \.offset) { _, pill in
                PillLabel(text: pill.text, style: style(pill.kind))
            }
        }
    }

    private func style(_ kind: PillState.Kind) -> PillLabel.Style {
        switch kind {
        case .clay: .clay
        case .payout, .plain: onTint ? .onTint : .plain
        }
    }
}

/// A section heading: a bold title and a hand-written count.
struct SectionTitle: View {
    let title: String
    var count: String?

    private var heading: some View {
        Text(title).lr(.heading).foregroundStyle(LR.Color.ink)
            .accessibilityAddTraits(.isHeader)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                heading
                Spacer(minLength: 8)
                if let count { HandText(count, .hand).foregroundStyle(LR.Color.accent) }
            }
            // At accessibility sizes the count drops under the title instead of squeezing it.
            VStack(alignment: .leading, spacing: 2) {
                heading
                if let count { HandText(count, .hand).foregroundStyle(LR.Color.accent) }
            }
        }
        .padding(.top, 6)
    }
}

// MARK: - level card

struct LevelCardView: View {
    let state: LevelCardState
    let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        levelText
                        coinsText
                        Spacer(minLength: 8)
                        toNextText
                    }
                    VStack(alignment: .leading, spacing: 2) { levelText; coinsText; toNextText }
                }
                // One row of small dots; the accessibility sizes use the two-row grid.
                LevelDotGrid(filled: state.filledDots, total: state.dotCount,
                             columns: typeSize.isAccessibilitySize ? 10 : state.dotCount)
                FlowRow(spacing: 6) {
                    PillLabel(text: state.tierText, dense: true)
                    PillLabel(text: state.slotsText, dense: true)
                    if let streak = state.streakText { PillLabel(text: streak, dense: true) }
                }
                if let goal = state.goal { goalBlock(goal) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lrCard(.surface, radius: LR.Radius.card)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityValue(state.accessibilityValue)
        .accessibilityHint("Shows what each level unlocks")
        .accessibilityAddTraits(.isButton)
    }

    private var levelText: some View {
        Text("Lv \(state.level)").lr(.levelInline).foregroundStyle(LR.Color.ink)
    }

    private var coinsText: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(state.balance)").lr(.titleCard).monospacedDigit()
                .foregroundStyle(state.isNegative ? LR.Color.clay : LR.Color.ink)
            Text("coins").lr(.caption).foregroundStyle(LR.Color.inkSecondary)
        }
    }

    private var toNextText: some View {
        Text("\(state.pointsToNext) to Lv \(state.level + 1)").lr(.caption).foregroundStyle(LR.Color.inkSecondary)
    }

    private func goalBlock(_ goal: LevelCardState.Goal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(goal.name).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                    Spacer(minLength: 8)
                    Text(goal.text).lr(.caption).monospacedDigit().foregroundStyle(LR.Color.inkSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.name).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                    Text(goal.text).lr(.caption).monospacedDigit().foregroundStyle(LR.Color.inkSecondary)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(LR.Color.dotEmpty)
                    Capsule().fill(LR.Color.fill).frame(width: proxy.size.width * goal.fraction)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - routine-style row (routines and the epic)

/// The frame routines, the epic and quests share: a doodle disc, the details, the controls, and an
/// optional footer along the bottom of the card. At accessibility sizes the controls drop under
/// the text.
private struct RowLayout<Details: View, Controls: View, Footer: View>: View {
    let doodle: DoodleKey
    var fill: CardFill = .surface
    @ViewBuilder let details: Details
    @ViewBuilder let controls: Controls
    @ViewBuilder let footer: Footer

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) { disc; details }
                    HStack(spacing: 0) { Spacer(minLength: 0); controls }
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    disc
                    details
                    controls
                }
            }
            footer
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard(fill, radius: LR.Radius.row)
        .environment(\.lrTint, fill.tint)
    }

    private var disc: some View {
        Circle().fill(fill.disc)
            .frame(width: 52, height: 52)
            .overlay { DoodleView(key: doodle, size: 28) }
    }
}

// MARK: - epic

/// The week's epic: a routine row with a flag in the disc, an "Epic" pill, the week as seven thin
/// segments along the bottom, and a tap on the card body that opens the detail. The complete
/// button and the `⋯` menu are buttons of their own, so a body tap never completes anything.
struct EpicCardView: View {
    let state: EpicCardState
    var actions: [CardAction] = []
    let onComplete: () -> Void

    @State private var expanded = false
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ink: Color { LR.Color.ink(on: .epic) }

    var body: some View {
        RowLayout(doodle: .flag, fill: .tint(.epic)) {
            details
        } controls: {
            HStack(spacing: 0) {
                CardMenuButton(actions: menuActions)
                CompleteButton(isDone: state.isDone, action: onComplete)
            }
        } footer: {
            SegmentedProgress(filled: state.segmentsFilled, total: state.segmentsTotal,
                              fill: ink, track: ink.opacity(0.3))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .cardElement(label: state.accessibilityLabel, value: state.accessibilityValue,
                     complete: state.isDone ? nil : onComplete,
                     actions: menuActions,
                     extra: [(title: expanded ? "Collapse details" : "Expand details", run: toggle)],
                     hint: expanded ? "Collapses the details" : "Expands the details")
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() }
    }

    /// The link rides in the menu as well as in the detail, like the other cards' menus.
    private var menuActions: [CardAction] {
        guard let url = state.launchURL else { return actions }
        return actions + [CardAction(title: "Open link", systemImage: "link") { openURL(url) }]
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                DoneTitle(text: state.title, isDone: state.isDone)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ink)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
            PillRow(pills: state.pills, onTint: true)
                .gainFloat(state.awardedPoints.map { "+\($0)" } ?? "", when: state.isDone)
            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(state.detailLines, id: \.self) { line in
                        Text(line).lr(.caption).foregroundStyle(ink)
                    }
                    if let url = state.launchURL {
                        Link("Open", destination: url)
                            .lr(.caption).foregroundStyle(ink).underline()
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                            .padding(.vertical, -12)
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - routine row

struct RoutineRowView: View {
    let state: RoutineRowState
    var actions: [CardAction] = []
    let onComplete: () -> Void
    var onSwitchVersion: () -> Void = {}

    private var ink: Color { LR.Color.ink(on: .routine) }

    var body: some View {
        RowLayout(doodle: state.doodle, fill: .tint(.routine)) {
            details
        } controls: {
            HStack(spacing: 0) {
                CardMenuButton(actions: actions)
                if !state.isSkipped {
                    CompleteButton(isDone: state.isDone, action: onComplete)
                }
            }
        } footer: {
            EmptyView()
        }
        .cardElement(label: state.accessibilityLabel, value: state.accessibilityValue,
                     complete: state.isDone || state.isSkipped ? nil : onComplete,
                     actions: actions,
                     extra: versionAction)
    }

    private var versionAction: [(title: String, run: () -> Void)] {
        state.version?.switchLabel.map { [(title: $0, run: onSwitchVersion)] } ?? []
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            DoneTitle(text: state.title, isDone: state.isDone)
            PillRow(pills: state.pills, onTint: true)
                .gainFloat(state.awardedPoints.map { "+\($0)" } ?? "", when: state.isDone)
            if let version = state.version {
                Text(version.note).lr(.caption).foregroundStyle(ink)
                if let label = version.switchLabel {
                    Button(label, action: onSwitchVersion)
                        .lr(.caption).foregroundStyle(ink)
                        .underline()
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        .padding(.vertical, -12)
                }
            }
            if let line = state.noteLine {
                Text(line).lr(.caption).foregroundStyle(ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - ahead

/// A flexible routine that can be done now: a routine row whose control is "Do now", which raises
/// the usual confirmation.
struct AheadCandidateRowView: View {
    let state: AheadCandidateState
    let onDoNow: () -> Void

    var body: some View {
        RowLayout(doodle: state.doodle, fill: .tint(.routine)) {
            VStack(alignment: .leading, spacing: 6) {
                DoneTitle(text: state.title, isDone: false)
                PillRow(pills: state.pills, onTint: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } controls: {
            Button("Do now", action: onDoNow).buttonStyle(PillButtonStyle())
        } footer: {
            EmptyView()
        }
        .cardElement(label: state.accessibilityLabel, value: state.accessibilityValue,
                     complete: nil, extra: [(title: "Do now", run: onDoNow)])
    }
}

// MARK: - quest rows

/// A quest as a routine-style row on its difficulty tint, open or done. The range pill becomes `+N`
/// once paid. The link lives in the `⋯` menu while the quest is open.
struct QuestRowView: View {
    let state: QuestCardState
    var actions: [CardAction] = []
    let onComplete: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        RowLayout(doodle: state.doodle, fill: .tint(state.tint)) {
            details
        } controls: {
            HStack(spacing: 0) {
                CardMenuButton(actions: menuActions)
                CompleteButton(isDone: state.isDone, action: onComplete)
            }
        } footer: {
            EmptyView()
        }
        .cardElement(label: state.accessibilityLabel, value: state.accessibilityValue,
                     complete: state.isDone ? nil : onComplete,
                     actions: menuActions)
    }

    private var menuActions: [CardAction] {
        guard !state.isDone, let url = state.launchURL else { return actions }
        return actions + [CardAction(title: "Open link", systemImage: "link") { openURL(url) }]
    }

    /// A finished micro-action group names its three actions; every other quest its drawn value.
    private var caption: String? {
        state.layout == .trivialGroup ? state.items.map(\.text).joined(separator: " · ") : state.subtitle
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            DoneTitle(text: state.title, isDone: state.isDone)
            if let caption {
                Text(caption).lr(.caption).foregroundStyle(LR.Color.ink(on: state.tint))
            }
            PillLabel(text: state.pillText, style: .onTint)
                .gainFloat(state.pillText, when: state.isDone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Three micro-actions in one wide mint tile, scored as a whole once all three are ticked.
struct MicroGroupTileView: View {
    let state: QuestCardState
    var actions: [CardAction] = []
    let onTick: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    DoneTitle(text: state.title, isDone: state.isDone, style: .heading)
                    if let subtitle = state.subtitle {
                        Text(subtitle).lr(.caption).foregroundStyle(LR.Color.ink(on: .trivial))
                    }
                }
                Spacer(minLength: 8)
                PillLabel(text: state.pillText, style: .onTint)
                    .gainFloat(state.pillText, when: state.isDone)
                CardMenuButton(actions: actions)
                    .padding(.top, -8).padding(.trailing, -8)
            }
            ForEach(Array(state.items.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 6) {
                    CompleteButton(isDone: item.isDone) { onTick(index) }
                    VStack(alignment: .leading, spacing: 1) {
                        DoneTitle(text: item.text, isDone: item.isDone)
                        if let variant = item.variant {
                            Text(variant).lr(.caption).foregroundStyle(LR.Color.ink(on: .trivial))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard(.tint(.trivial), radius: LR.Radius.tile)
        .environment(\.lrTint, .trivial)
        .cardElement(label: state.accessibilityLabel, value: state.accessibilityValue,
                     complete: nil,
                     actions: actions,
                     extra: state.items.enumerated().filter { !$0.element.isDone }.map { index, item in
                         (title: "Tick \(item.text)", run: { onTick(index) })
                     })
    }
}

/// The hidden quest before it exists: a button once every slot is cleared, a lock until then.
struct HiddenGateTile: View {
    let unlocked: Bool
    let onReveal: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if unlocked {
            Button(action: onReveal) { content }
                .buttonStyle(PressableCardStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Reveal the hidden quest")
                .accessibilityAddTraits(.isButton)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Hidden quest, locked")
                .accessibilityValue("Clear every slot to unlock")
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            if unlocked {
                DoodleView(key: .sparkle, size: 40, tint: LR.Color.ink(on: .hidden))
            } else {
                Image(systemName: "lock").font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(LR.Color.ink(on: .hidden))
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
            }
            Text(unlocked ? "Reveal the hidden quest" : "Clear every slot to unlock")
                .lr(.bodyStrong)
                .foregroundStyle(LR.Color.ink(on: .hidden))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .lrCard(.tint(.hidden), radius: LR.Radius.tile)
        .contentShape(RoundedRectangle(cornerRadius: LR.Radius.tile, style: .continuous))
    }
}

// MARK: - records and plain rows

/// A slot that is no longer today's ask: a small strikethrough record, nothing to do.
struct ReplacedRowView: View {
    let state: ReplacedRowState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            PillLabel(text: state.code)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title).lr(.bodyStrong).strikethrough()
                    .foregroundStyle(LR.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(state.note).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.title), \(state.note)")
    }
}

/// A plain card row for the calendar's "Did not finish" list: a title, a caption and whatever
/// sits at the trailing edge.
struct RecordRowView<Trailing: View>: View {
    let title: String
    var caption: String?
    var secondary = false
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lr(.bodyStrong)
                    .foregroundStyle(secondary ? LR.Color.inkSecondary : LR.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption {
                    Text(caption).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard(.surface, radius: LR.Radius.row)
    }
}

/// Generation and action errors: clay on its tinted ground, never alarm red.
struct BannerView: View {
    var title: String?
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title { Text(title).lr(.bodyStrong).foregroundStyle(LR.Color.clay) }
            Text(message).lr(.caption).foregroundStyle(LR.Color.clay)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard(.clayBg, radius: LR.Radius.row)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - history rows (day detail)

/// The 44 pt mark at the trailing edge of a read-only row, where Today has the complete button:
/// the filled check for done, an open ring for not done, a ring with a dash for skipped or
/// replaced. Never the only signal: the row's status text says the same.
struct HistoryMark: View {
    /// `dropped` is a dash (swapped, cancelled); `missed` a cross (the settlement gave up on it).
    enum Kind { case done, open, dropped, missed }
    let kind: Kind

    @Environment(\.lrTint) private var tint

    var body: some View {
        let ring = tint.map(LR.Color.ink(on:)) ?? LR.Color.iconNeutral
        ZStack {
            Circle().strokeBorder(ring, lineWidth: 1.5).opacity(kind == .done ? 0 : 1)
            Circle().fill(DoneMark.fill(on: tint)).opacity(kind == .done ? 1 : 0)
            if kind == .done {
                HandCheck()
                    .stroke(DoneMark.check(on: tint), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 20, height: 20)
            }
            if kind == .dropped { Capsule().fill(ring).frame(width: 12, height: 2) }
            if kind == .missed {
                ForEach([45.0, -45.0], id: \.self) { angle in
                    Capsule().fill(ring).frame(width: 14, height: 2).rotationEffect(.degrees(angle))
                }
            }
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

/// A quest or a routine as it was on a past day: the same row frame as Today's, read-only. The
/// pills carry the slot, what it paid and the ratings; a replaced row is struck through and quiet.
struct HistoryRowView: View {
    let doodle: DoodleKey
    var fill: CardFill = .surface
    let title: String
    /// A replaced row: struck through in the secondary colour.
    var dropped = false
    /// The micro-action group's lines; when present they stand in for the title.
    var items: [(text: String, isDone: Bool)] = []
    let status: String
    var pills: [PillState] = []
    let mark: HistoryMark.Kind
    let accessibilityLabel: String
    let accessibilityValue: String

    var body: some View {
        RowLayout(doodle: doodle, fill: fill) {
            details
        } controls: {
            HistoryMark(kind: mark)
        } footer: {
            EmptyView()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var ink: Color { fill.tint.map(LR.Color.ink(on:)) ?? LR.Color.ink }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            if items.isEmpty {
                DoneTitle(text: title, isDone: dropped, color: dropped ? LR.Color.inkSecondary : nil)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(ink)
                            .accessibilityHidden(true)
                        Text(item.text).lr(.bodyStrong).foregroundStyle(ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text(status).lr(.caption)
                .foregroundStyle(fill.tint == nil ? LR.Color.inkSecondary : ink)
                .fixedSize(horizontal: false, vertical: true)
            if !pills.isEmpty { PillRow(pills: pills, onTint: fill.tint != nil) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
