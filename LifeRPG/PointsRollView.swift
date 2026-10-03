import LifeRPGCore
import SwiftUI

/// The rating scale shared by the payout card and the Library page, so neither keeps its own copy.
/// `QuestRating` stores every answer with its date: a changed mind is a new row, never an overwrite.
enum RatingScale {
    static let steps: [(value: Int, symbol: String, label: String)] = [
        (-2, "hand.thumbsdown.fill", "Hated it"),
        (-1, "hand.thumbsdown", "Rather not"),
        (0, "minus", "Fine"),
        (1, "hand.thumbsup", "Liked it"),
        (2, "hand.thumbsup.fill", "Loved it"),
    ]

    static func label(for value: Int) -> String {
        steps.first { $0.value == value }?.label ?? "\(value)"
    }
}

// MARK: - what the card is about and what it offers

/// The item the card is about: a 28 pt disc in the item's tint with its doodle, then its title.
/// A neutral disc (no tint) is for a card that is about no particular item (a level-up).
struct MomentHeader {
    var doodle: DoodleKey
    var tint: QuestTint?
    var title: String
    var subtitle: String?
}

extension MomentHeader {
    init(_ state: QuestCardState) {
        self.init(doodle: state.doodle, tint: state.tint, title: state.title,
                  subtitle: state.layout == .trivialGroup ? state.items.map(\.text).joined(separator: " · ")
                                                          : state.subtitle)
    }

    init(_ state: EpicCardState) {
        self.init(doodle: .flag, tint: .epic, title: state.title)
    }

    init(_ state: RoutineRowState) {
        self.init(doodle: state.doodle, tint: .routine, title: state.title)
    }
}

/// Where the card is. `ask` is the confirmation; the other three are the payout, in order.
enum MomentStage: Equatable {
    case ask, rolling, landed, rate
}

/// "Mark as done?": one pill, or two when a routine done ahead on a low day has lighter versions
/// (each with the payout it leads to), and a quiet `Not yet`.
struct MomentAsk {
    /// What sits between the header and the buttons. A quest's payout is rolled, so a `?` box
    /// stands in for it. A routine's is fixed and known now, so it is a pill under the title (or on
    /// each button, when there are two choices) and there is no reel at all.
    enum Lead {
        case reel
        case fixed(pill: String?)
    }

    struct Choice: Identifiable {
        let title: String
        var pill: String?
        var outlined = false
        let action: () -> Void

        var id: String { title }
    }

    /// Spoken when the card appears, with the item's title after it.
    var question = "Mark as done?"
    var lead = Lead.reel
    var choices: [Choice]
    var footnote: String?
    let notYet: () -> Void
}

/// A priced confirmation, an explanation or an announcement: a paragraph, one ink pill and,
/// where there is a way out, a quiet one.
struct MomentNotice {
    var message: String?
    let primary: String
    var quiet: String?
    let confirm: () -> Void
    /// The dim and VoiceOver's escape gesture.
    let dismiss: () -> Void
}

/// A payout that is already written to the ledger. The card only describes it.
struct MomentPayout: Identifiable {
    /// A quest's payout is rolled and the card plays the reel. A routine's is fixed: there is
    /// nothing to roll, so the card goes straight to the number.
    enum Amount {
        case rolled(Scoring.Breakdown)
        case fixed(Int)
    }

    let id: UUID
    let amount: Amount
    /// The rating you picked, or nil when you left without one. Always optional: this card appears
    /// several times a day, and a reward screen that demands an answer is a toll booth.
    let onFinish: (Int?) -> Void

    init(id: UUID, breakdown: Scoring.Breakdown, onFinish: @escaping (Int?) -> Void) {
        self.init(id: id, amount: .rolled(breakdown), onFinish: onFinish)
    }

    init(id: UUID, fixed awarded: Int, onFinish: @escaping (Int?) -> Void) {
        self.init(id: id, amount: .fixed(awarded), onFinish: onFinish)
    }

    init(id: UUID, amount: Amount, onFinish: @escaping (Int?) -> Void) {
        self.id = id
        self.amount = amount
        self.onFinish = onFinish
    }

    var awarded: Int {
        switch amount {
        case .rolled(let breakdown): breakdown.awarded
        case .fixed(let value): value
        }
    }

    var breakdown: Scoring.Breakdown? {
        if case .rolled(let breakdown) = amount { return breakdown }
        return nil
    }

    var isFixed: Bool { breakdown == nil }
}

enum MomentContent {
    case ask(MomentAsk)
    case notice(MomentNotice)
    case payout(MomentPayout)
}

// MARK: - the reel

/// Where the throwaway strip is. Frozen for the gallery, which draws a phase without playing it.
enum ReelClock {
    case running(since: Date, duration: TimeInterval)
    case frozen(Double)

    /// A row index along the strip, decelerating: the numbers blur past and settle on the last frame.
    func position(at date: Date, frameCount: Int) -> Double {
        let fraction: Double
        switch self {
        case .running(let start, let duration): fraction = min(max(date.timeIntervalSince(start) / duration, 0), 1)
        case .frozen(let value): fraction = value
        }
        let eased = 1 - pow(1 - fraction, 3)
        return eased * Double(max(frameCount - 1, 0))
    }
}

/// The box the number lives in. `?` while asking, blurred numbers scrolling through a band of the
/// item's tint while rolling, the landed number with its decorative neighbours once it stops.
/// The strip's numbers are `PayoutReel` frames: discarded, never the payout.
private struct ReelBox: View {
    let stage: MomentStage
    let tint: QuestTint?
    let awarded: Int?
    let range: ClosedRange<Int>?
    let frames: [Int]
    let clock: ReelClock

    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var k: CGFloat { min(scale, 1.4) }
    private var bandColor: Color { tint?.color ?? LR.Color.accent }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LR.Color.tabPill)
            if stage != .ask { band.transition(.opacity) }
            content
        }
        .frame(height: 96 * k)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            if stage == .landed, !reduceMotion { SparkleBurst() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch stage {
        case .ask: "Payout, rolled when you complete"
        case .rolling: range.map { "Rolling, pays \(PresentationText.spokenRange($0))" } ?? "Rolling"
        case .landed, .rate: awarded.map { "Paid \($0) coins" } ?? "Paid"
        }
    }

    private var band: some View {
        Rectangle().fill(bandColor.opacity(0.25))
            .frame(height: 50 * k)
            .overlay(alignment: .top) { Rectangle().fill(bandColor).frame(height: 1.5) }
            .overlay(alignment: .bottom) { Rectangle().fill(bandColor).frame(height: 1.5) }
    }

    @ViewBuilder private var content: some View {
        switch stage {
        case .ask, .rate:
            HandText("?", .handDisplay, balanced: true).foregroundStyle(LR.Color.ink)
        case .rolling:
            strip.transition(.opacity)
        case .landed:
            landed.transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
    }

    private var strip: some View {
        TimelineView(.animation) { timeline in
            let position = clock.position(at: timeline.date, frameCount: frames.count)
            let base = Int(position.rounded(.down))
            ZStack {
                ForEach((base - 2)...(base + 2), id: \.self) { index in
                    if frames.indices.contains(index) {
                        HandText("\(frames[index])", .handTitle, balanced: true)
                            .foregroundStyle(LR.Color.ink)
                            .blur(radius: 2.2)
                            .offset(y: (Double(index) - position) * 40 * k)
                    }
                }
            }
        }
    }

    private var landed: some View {
        let neighbours = awarded.flatMap { value in range.map { PayoutReel.neighbours(of: value, in: $0) } }
        return ZStack {
            // Smaller and dim, and without the `+`, so neither can be read as a payout.
            if let before = neighbours?.before {
                HandText("\(before)", .hand, balanced: true).foregroundStyle(LR.Color.inkSecondary)
                    .scaleEffect(0.8).offset(y: -36 * k)
            }
            if let after = neighbours?.after {
                HandText("\(after)", .hand, balanced: true).foregroundStyle(LR.Color.inkSecondary)
                    .scaleEffect(0.8).offset(y: 36 * k)
            }
            HandText(awarded.map { "+\($0)" } ?? "", .handDisplay, balanced: true).foregroundStyle(LR.Color.ink)
        }
    }
}

/// A few sparkle doodles thrown out from the band as the number lands.
private struct SparkleBurst: View {
    @State private var out = false

    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                let angle = Double(index) * .pi / 3 + 0.35
                DoodleView(key: .sparkle, size: index.isMultiple(of: 2) ? 24 : 17, tint: LR.Color.ink)
                    .offset(x: cos(angle) * (out ? 96 : 20), y: sin(angle) * (out ? 30 : 6))
                    .scaleEffect(out ? 1.15 : 0.4)
                    .opacity(out ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { withAnimation(.easeOut(duration: 0.8)) { out = true } }
    }
}

// MARK: - the card

/// The card as drawn at one phase. It plays nothing: `MomentCard` owns the timing, and the gallery
/// draws each phase with fixed values.
struct MomentCardFace: View {
    let header: MomentHeader
    let content: MomentContent
    /// Only read for a payout; an ask is always `.ask`.
    var stage: MomentStage = .rolling
    var frames: [Int] = []
    var clock: ReelClock = .frozen(0)
    var picked: Int?
    var onPick: (Int) -> Void = { _ in }
    var onDone: () -> Void = {}
    /// Changes when a notice's content is swapped for another (a refused reroll), so it fades in place.
    var noticeKey = ""

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var focus: Int?
    @ScaledMetric(relativeTo: .body) private var disc: CGFloat = 28

    /// What a one-choice ask's buttons take, and the least the rolling and landed captions keep
    /// under the reel. The reel box and the row above it stay the same size in every phase; the card
    /// itself shortens and lengthens in place (`MomentCard` animates its height).
    private static let controlsHeight: CGFloat = 106
    private static let captionHeight: CGFloat = 52

    private var reelStage: MomentStage? {
        switch content {
        case .ask(let ask): if case .reel = ask.lead { .ask } else { nil }
        case .payout(let payout): payout.isFixed ? nil : stage
        case .notice: nil
        }
    }

    /// The fixed payout pill of a routine's ask, in the row a quest's range pill uses.
    private var fixedPill: String? {
        if case .ask(let ask) = content, case .fixed(let pill) = ask.lead { return pill }
        return nil
    }

    private var payout: MomentPayout? {
        if case .payout(let p) = content { return p }
        return nil
    }

    private var swap: AnyTransition {
        reduceMotion ? .opacity
                     : .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)),
                                  removal: .opacity.animation(.easeOut(duration: 0.08)))
    }

    var body: some View {
        VStack(spacing: 14) {
            headerRow
            if let reelStage { reelSection(reelStage) }
            if let fixedPill { fixedPillRow(fixedPill) }
            if let payout, payout.isFixed { fixedResult(payout.awarded) }
            switch content {
            case .ask(let ask): askControls(ask).transition(swap)
            case .notice(let notice): noticeBody(notice).id(noticeKey).transition(swap)
            case .payout(let payout): payoutBottom(payout).transition(swap)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .lrCard(.surface, radius: 24)
    }

    // MARK: header

    private var headerRow: some View {
        HStack(spacing: 10) {
            Circle().fill(header.tint?.color ?? LR.Color.tabPill)
                .frame(width: min(disc, 48), height: min(disc, 48))
                .overlay {
                    DoodleView(key: header.doodle, size: min(disc, 48) * 0.68,
                               tint: header.tint.map(LR.Color.ink(on:)) ?? LR.Color.ink)
                }
            VStack(spacing: 2) {
                Text(header.title).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = header.subtitle {
                    Text(subtitle).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: the reel and what hangs off it

    private func reelSection(_ stage: MomentStage) -> some View {
        VStack(spacing: 10) {
            if stage == .rate {
                HandText(payout.map { "+\($0.awarded)" } ?? "", .handTitle, balanced: true).foregroundStyle(LR.Color.ink)
                    .transition(.opacity)
                    .accessibilityLabel(payout.map { "Paid \($0.awarded) coins" } ?? "")
            } else {
                rangeRow(stage)
                ReelBox(stage: stage, tint: header.tint, awarded: payout?.awarded,
                        range: payout?.breakdown?.payoutRange, frames: frames, clock: clock)
                    .transition(.opacity)
            }
        }
    }

    private func fixedPillRow(_ pill: String) -> some View {
        PillLabel(text: pill, style: .plain)
            .transition(.opacity)
            .accessibilityLabel("Pays \(pill) coins")
    }

    /// A routine's payout: the number it paid, big, then the rating row below. No reel and no
    /// sparkles, since there was nothing to roll.
    private func fixedResult(_ awarded: Int) -> some View {
        VStack(spacing: 2) {
            HandText("+\(awarded)", .handDisplay, balanced: true).foregroundStyle(LR.Color.ink)
            Text("paid").lr(.caption).foregroundStyle(LR.Color.sectionTitle)
        }
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Paid \(awarded) coins")
    }

    /// Always as tall as the pill, so the box does not move when it appears and goes.
    private func rangeRow(_ stage: MomentStage) -> some View {
        ZStack {
            Color.clear.frame(height: 26)
            if let range = payout?.breakdown?.payoutRange, range.count > 1, stage != .ask {
                PillLabel(text: PresentationText.range(range), style: .plain)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: ask

    private func askControls(_ ask: MomentAsk) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(ask.choices.enumerated()), id: \.element.id) { index, choice in
                Button(action: choice.action) { choiceLabel(choice) }
                    .buttonStyle(MomentPillStyle(outlined: choice.outlined))
                    .accessibilityFocused($focus, equals: index)
            }
            if let footnote = ask.footnote {
                Text(footnote).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            quietButton("Not yet", action: ask.notYet)
        }
        .frame(minHeight: Self.controlsHeight, alignment: .top)
        .task { focus = 0 }
    }

    private func choiceLabel(_ choice: MomentAsk.Choice) -> some View {
        HStack(spacing: 10) {
            Text(choice.title)
            if let pill = choice.pill {
                Text(pill).lr(.pill)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(choice.outlined ? LR.Color.pillFill : LR.Color.onFill.opacity(0.2)))
            }
        }
    }

    private func quietButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .lr(.bodyStrong).foregroundStyle(LR.Color.inkSecondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }

    // MARK: notice

    private func noticeBody(_ notice: MomentNotice) -> some View {
        VStack(spacing: 6) {
            if let message = notice.message {
                Text(message).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
            }
            Button(notice.primary, action: notice.confirm)
                .buttonStyle(MomentPillStyle())
                .accessibilityFocused($focus, equals: 0)
            if let quiet = notice.quiet { quietButton(quiet, action: notice.dismiss) }
        }
        .task { focus = 0 }
    }

    // MARK: payout

    @ViewBuilder private func payoutBottom(_ payout: MomentPayout) -> some View {
        // A fixed payout has no reel to wait for: it is already at the rating.
        switch payout.isFixed ? .rate : stage {
        case .ask, .rolling:
            Text("rolling…").lr(.caption).foregroundStyle(LR.Color.sectionTitle)
                .frame(maxWidth: .infinity, minHeight: Self.captionHeight, alignment: .top)
                .accessibilityHidden(true)
        case .landed:
            if let breakdown = payout.breakdown {
                landedCaption(breakdown)
                    .frame(maxWidth: .infinity, minHeight: Self.captionHeight, alignment: .top)
            }
        case .rate:
            rateBlock
        }
    }

    /// Only says something beyond `paid` when there is something to say: the hidden quest's flat
    /// bonus, the group that isn't a roll, a low-energy day that paid more than the band suggests.
    private func landedCaption(_ breakdown: Scoring.Breakdown) -> some View {
        VStack(spacing: 8) {
            Text("paid").lr(.caption).foregroundStyle(LR.Color.sectionTitle)
            if breakdown.bonus > 0 { PillLabel(text: "★ +\(breakdown.bonus)", style: .plain) }
            if let note = Self.note(breakdown) {
                Text(note).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityHidden(true)
    }

    static func note(_ breakdown: Scoring.Breakdown) -> String? {
        if !breakdown.isRolled { return "the group scores \(breakdown.rolled) as a whole, not a roll" }
        if breakdown.multiplier > 1 { return String(format: "×%.1f low energy", breakdown.multiplier) }
        return nil
    }

    /// Asked here rather than on a separate screen because this is the one moment the answer is
    /// cheap and honest: you have just done the thing.
    private var rateBlock: some View {
        VStack(spacing: 10) {
            HandText("how did that feel?", .hand, balanced: true).foregroundStyle(LR.Color.accent)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { ratingButtons(0..<RatingScale.steps.count) }
                VStack(spacing: 6) {
                    HStack(spacing: 6) { ratingButtons(0..<3) }
                    HStack(spacing: 6) { ratingButtons(3..<RatingScale.steps.count) }
                }
            }
            quietButton("Done", action: onDone)
        }
    }

    private func ratingButtons(_ indices: Range<Int>) -> some View {
        ForEach(RatingScale.steps[indices], id: \.value) { step in
            let selected = picked == step.value
            Button { onPick(step.value) } label: {
                Image(systemName: step.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(selected ? LR.Color.onFill : LR.Color.ink)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(selected ? LR.Color.fill : LR.Color.tabPill))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(step.label)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}

/// The full-width pill of the card: filled ink, or outlined for the second of two choices.
private struct MomentPillStyle: ButtonStyle {
    var outlined = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lr(.heading)
            .foregroundStyle(outlined ? LR.Color.ink : LR.Color.onFill)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                if outlined {
                    Capsule().strokeBorder(LR.Color.ink, lineWidth: 1.5)
                } else {
                    Capsule().fill(LR.Color.fill)
                }
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.8 : 1)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}

// MARK: - the overlay

private struct MomentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The one centered card of the Today page: a confirmation, its payout, a priced confirmation, an
/// explanation or an announcement, on a dimmed page.
///
/// **Nothing here decides anything.** The points were rolled inside `Completion.complete` and
/// written to the ledger before the card switches from `ask` to the payout, and `Scoring.Breakdown`
/// only describes that result. The numbers flashing past while it rolls are `PayoutReel` frames,
/// discarded, never the payout: a reveal that rolled its own number would show you something other
/// than what you were paid, and re-rolling until it is good is what `PLAN.md` §3's "completion is
/// final" exists to prevent.
///
/// The phases play in place, in one layer, so a confirmation does not give way to a second screen.
/// A tap on the dim means the quiet answer: `Not yet` while asking, skip ahead while the payout
/// plays, and leave (keeping any rating) once it asks how it felt.
struct MomentCard: View {
    let header: MomentHeader
    let content: MomentContent
    /// Changes when a notice's content is replaced by another in place.
    var noticeKey = ""

    @State private var stage: MomentStage = .rolling
    @State private var frames: [Int] = []
    @State private var clock: ReelClock = .frozen(0)
    @State private var picked: Int?
    @State private var contentHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private static let frameCount = 16
    private static let rollSeconds = 1.5
    private static let landedSeconds = 0.9
    private static let rateTimeoutSeconds = 8.0

    private var payout: MomentPayout? {
        if case .payout(let p) = content { return p }
        return nil
    }

    /// Where the card is. A fixed payout has no roll to play, so it is at the rating from the start.
    private var phase: MomentStage { payout?.isFixed == true ? .rate : stage }

    private var phaseAnimation: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .snappy }

    var body: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.6 : 0.42)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: dimTapped)
                .accessibilityHidden(true)
                .transition(.opacity)

            GeometryReader { geo in
                ScrollView {
                    MomentCardFace(header: header, content: content, stage: phase, frames: frames,
                                   clock: clock, picked: picked, onPick: pick, onDone: finish,
                                   noticeKey: noticeKey)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(key: MomentHeightKey.self, value: proxy.size.height)
                            }
                        }
                        .overlay {
                            if payout != nil, phase == .landed {
                                Color.clear.contentShape(Rectangle()).onTapGesture(perform: advance)
                            }
                        }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollClipDisabled()
                .onPreferenceChange(MomentHeightKey.self) { contentHeight = $0 }
                .frame(width: min(320, geo.size.width - 80),
                       height: contentHeight > 0 ? min(contentHeight, geo.size.height - 112) : nil)
                .animation(phaseAnimation, value: contentHeight)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.94).combined(with: .opacity))
            }
            .ignoresSafeArea()
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, escape)
        .task(id: payout?.id) { await play() }
        .task(id: rateTimerID) { await expireRate() }
        .task(id: askAnnouncement) {
            if let askAnnouncement { AccessibilityNotification.Announcement(askAnnouncement).post() }
        }
    }

    // MARK: taps

    private var askAnnouncement: String? {
        if case .ask(let ask) = content { return "\(ask.question) \(header.title)" }
        return nil
    }

    private func dimTapped() {
        switch content {
        case .ask(let ask): ask.notYet()
        case .notice(let notice): notice.dismiss()
        case .payout:
            switch phase {
            case .ask, .rolling: land()
            case .landed: advance()
            case .rate: finish()
            }
        }
    }

    private func escape() {
        switch content {
        case .ask(let ask): ask.notYet()
        case .notice(let notice): notice.dismiss()
        case .payout: finish()
        }
    }

    private func pick(_ value: Int) {
        Haptics.selection()
        withAnimation(phaseAnimation) { picked = value }
    }

    private func finish() { payout?.onFinish(picked) }

    // MARK: the sequence

    /// Rolls through throwaway frames, lands on the awarded number, holds it for a moment, then asks.
    /// A payout with nothing to roll (the micro-action group, a fixed span) and Reduce Motion both
    /// go straight to the landed number.
    private func play() async {
        guard let payout else { return }
        picked = nil
        guard let breakdown = payout.breakdown else {
            AccessibilityNotification.Announcement("Paid \(payout.awarded) coins").post()
            return
        }
        stage = .rolling
        var rng = SystemRandomNumberGenerator()
        frames = PayoutReel.frames(range: breakdown.payoutRange, awarded: breakdown.awarded,
                                   count: Self.frameCount, using: &rng)
        if reduceMotion || frames.isEmpty {
            land()
        } else {
            clock = .running(since: Date(), duration: Self.rollSeconds)
            await wait(Self.rollSeconds + 0.1, while: .rolling)
            land()
        }
        await wait(Self.landedSeconds, while: .landed)
        advance()
    }

    private func land() {
        guard let payout, stage == .rolling else { return }
        withAnimation(phaseAnimation) { stage = .landed }
        Haptics.impact(.rigid)
        AccessibilityNotification.Announcement("Paid \(payout.awarded) coins").post()
        if (payout.breakdown?.bonus ?? 0) > 0 {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                Haptics.impact(.soft)
            }
        }
    }

    private func advance() {
        guard payout != nil, stage == .landed else { return }
        withAnimation(phaseAnimation) { stage = .rate }
    }

    /// Sleeps in short steps so a tap that moves the stage on ends the wait.
    private func wait(_ seconds: Double, while expected: MomentStage) async {
        let end = Date().addingTimeInterval(seconds)
        while stage == expected, Date() < end, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    /// Restarts on every pick. The card closes itself eventually, so one left open on a phone put
    /// down mid-tap doesn't sit there (with a rating nobody has written yet) until the app is quit.
    private var rateTimerID: Int? { payout != nil && phase == .rate ? (picked ?? 99) : nil }

    private func expireRate() async {
        guard rateTimerID != nil else { return }
        try? await Task.sleep(for: .seconds(Self.rateTimeoutSeconds))
        if !Task.isCancelled { finish() }
    }
}
