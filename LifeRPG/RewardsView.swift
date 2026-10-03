import LifeRPGCore
import SwiftData
import SwiftUI

/// Where coins go that isn't a row on the today page (`PLAN.md` §6): real-world rewards you enter
/// yourself, priced by `RewardPricing` from what they cost, and the streak freeze, bought after a
/// break to patch it. Rerolls, cancellations and the epic extension live on the rows they act on.
///
/// Every rule and price is Core's; this page hands it the rows its queries already hold.
struct RewardsView: View {
    let today: String
    /// Set while the confirmation card is up, so the floating tab bar fades out under the dim, as on Today.
    var hidesTabBar: Binding<Bool> = .constant(false)

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Reward.name) private var rewards: [Reward]
    @Query private var ledger: [LedgerEntry]
    @Query private var quests: [DailyQuest]

    @State private var editing: Editing?
    @State private var confirming: Confirm?
    @State private var actionError: String?

    private struct Editing: Identifiable {
        let id = UUID()
        var reward: Reward?
    }

    private enum Confirm: Identifiable {
        case redeem(Reward)
        case freeze(String)

        var id: String {
            switch self {
            case .redeem(let r): "redeem-\(r.id)"
            case .freeze(let day): "freeze-\(day)"
            }
        }
    }

    private var balance: Int { Economy.balance(ledger) }
    private var active: [Reward] { rewards.filter(\.isActive) }
    private var completedDays: Set<String> { Streak.completedDayKeys(quests) }
    private var frozenDays: Set<String> { Streak.frozenDayKeys(ledger) }
    private var repairable: String? {
        Streak.repairableDay(days: completedDays, frozen: frozenDays, today: today)
    }

    /// Redemptions of rewards, newest first — archived rewards included, since they were bought.
    private var redeemed: [LedgerEntry] {
        let ids = Set(rewards.map(\.id))
        return ledger
            .filter { $0.kind == Economy.Kind.redeem.rawValue && ($0.refID.map(ids.contains) ?? false) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LR.Spacing.sectionGap) {
                    if let actionError { BannerView(message: actionError) }
                    balanceCard
                    if let repairable { freezeSection(repairable) }
                    goalSection
                    rewardsSection
                    redeemedSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .reservingTabBarSpace()
            .background(LR.Color.canvas.ignoresSafeArea())
            .navigationTitle("Rewards")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = Editing(reward: nil) } label: {
                        Image(systemName: "plus").foregroundStyle(LR.Color.ink)
                    }
                    .accessibilityLabel("Add a reward")
                }
            }
            .sheet(item: $editing) { e in
                RewardEditor(reward: e.reward)
            }
        }
        // Behind the card the page is not reachable, for VoiceOver either.
        .accessibilityHidden(confirming != nil)
        .overlay {
            if let confirming {
                MomentCard(header: header(for: confirming), content: content(for: confirming))
            }
        }
        .onChange(of: confirming == nil) { hidesTabBar.wrappedValue = confirming != nil }
        .onDisappear { hidesTabBar.wrappedValue = false }
    }

    // MARK: sections

    /// The balance as it is: the ledger's sum, in clay and on the clay ground while it is negative.
    private var balanceCard: some View {
        let debt = Purchase.blocked(cost: 0, balance: balance)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Coins").lr(.caption).foregroundStyle(debt == nil ? LR.Color.inkSecondary : LR.Color.clay)
            HandText("\(balance)", .handDisplay).monospacedDigit()
                .foregroundStyle(debt == nil ? LR.Color.ink : LR.Color.clay)
            if let debt {
                Text("\(debt.description)").lr(.caption).foregroundStyle(LR.Color.clay)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard(debt == nil ? .surface : .clayBg, radius: LR.Radius.card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coin balance")
        .accessibilityValue("\(balance) coins" + (debt.map { ", \($0.description)" } ?? ""))
    }

    private func freezeSection(_ day: String) -> some View {
        let cost = freezeCost(day)
        let blocked = Redemption.blockedFreeze(days: completedDays, frozen: frozenDays,
                                               today: today, balance: balance, cost: cost)
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Streak")
            RewardCard(doodle: .sparkle, title: "Missed \(day)",
                       caption: "A freeze covers it, and the streak runs on as if it hadn't broken.",
                       pills: [], blocked: blocked,
                       buttonTitle: "Freeze · \(cost == 0 ? "free" : "\(cost)")",
                       actions: [], goal: nil) { show(.freeze(day)) }
        }
    }

    @ViewBuilder private var goalSection: some View {
        if let reward = SavingsGoal.goal(rewards),
           let progress = SavingsGoal.progress(rewards: rewards, ledger: ledger, today: today) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Saving for")
                rewardCard(reward, goal: progress)
            }
        }
    }

    private var rewardsSection: some View {
        let goalID = SavingsGoal.goal(rewards)?.id
        let rest = active.filter { $0.id != goalID }
        return VStack(alignment: .leading, spacing: 10) {
            if active.isEmpty {
                emptyState
            } else if !rest.isEmpty {
                SectionTitle(title: "Rewards")
                ForEach(rest) { rewardCard($0, goal: nil) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Circle().fill(LR.Color.pillFill).frame(width: 64, height: 64)
                .overlay { DoodleView(key: .sparkle, size: 34) }
                .accessibilityHidden(true)
            HandText("Something worth saving for", .handTitle, balanced: true, wraps: true).foregroundStyle(LR.Color.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Add a treat or a purchase you want. Its coin price follows from what it costs.")
                .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add a reward") { editing = Editing(reward: nil) }
                .buttonStyle(SheetPrimaryButtonStyle())
                .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .lrCard(.surface, radius: LR.Radius.card)
    }

    @ViewBuilder private var redeemedSection: some View {
        if !redeemed.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Redeemed")
                VStack(spacing: 0) {
                    ForEach(Array(redeemed.prefix(30).enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Rectangle().fill(LR.Color.divider).frame(height: 1) }
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.note).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(entry.dayKey).lr(.caption).monospacedDigit()
                                    .foregroundStyle(LR.Color.inkSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(entry.points)").lr(.bodyStrong).monospacedDigit()
                                .foregroundStyle(LR.Color.inkSecondary)
                        }
                        .padding(12)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(entry.note)
                        .accessibilityValue("\(entry.dayKey), \(entry.points) coins")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .lrCard(.surface, radius: LR.Radius.row)
            }
        }
    }

    // MARK: rows

    private func rewardCard(_ r: Reward, goal: SavingsGoal.Progress?) -> some View {
        let coins = RewardPricing.coins(for: r)
        return RewardCard(
            doodle: DoodleKey.forText(r.name), title: r.name, caption: nil,
            pills: [("\(coins) coins", .plain)]
                + (r.estimatedCost > 0 ? [("≈ \(r.estimatedCost.formatted())", .plain)] : []),
            blocked: Redemption.blocked(redeeming: r, balance: balance),
            buttonTitle: "Redeem",
            actions: [
                // The one reward the today page's HUD tracks (`SavingsGoal`).
                CardAction(title: r.isGoal ? "Unpin goal" : "Set as goal",
                           systemImage: r.isGoal ? "flag.slash" : "flag") { toggleGoal(r) },
                CardAction(title: "Edit", systemImage: "pencil") { editing = Editing(reward: r) },
                // Archived, never deleted: past redemptions still point at it.
                CardAction(title: "Archive", systemImage: "archivebox") { archive(r) },
            ],
            goal: goal) { show(.redeem(r)) }
    }

    // MARK: confirmation
    // The same centered card as Today's priced confirmations: the item in the header, the price and
    // what it does as a small paragraph, one ink pill and a quiet way out. Nothing is rolled.

    private func show(_ next: Confirm?) {
        withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.22)) { confirming = next }
    }

    private func header(for c: Confirm) -> MomentHeader {
        switch c {
        case .redeem(let r): MomentHeader(doodle: DoodleKey.forText(r.name), tint: nil, title: r.name)
        case .freeze(let day): MomentHeader(doodle: .sparkle, tint: nil, title: "Missed \(day)", subtitle: "Streak freeze")
        }
    }

    private func content(for c: Confirm) -> MomentContent {
        let cost = cost(of: c)
        return .notice(MomentNotice(message: message(for: c, cost: cost),
                                    primary: primary(for: c, cost: cost),
                                    quiet: "Not yet",
                                    confirm: { buy(c) },
                                    dismiss: { show(nil) }))
    }

    private func primary(for c: Confirm, cost: Int) -> String {
        switch c {
        case .redeem: "Redeem \(cost)"
        case .freeze: cost == 0 ? "Use this month's free one" : "Spend \(cost)"
        }
    }

    private func message(for c: Confirm, cost: Int) -> String {
        let price = cost == 0 ? "Free" : "\(cost) coins"
        switch c {
        case .redeem: return price
        case .freeze(let day): return "\(price). Covers \(day) so the streak doesn't break there."
        }
    }

    // MARK: actions

    private func cost(of c: Confirm) -> Int {
        switch c {
        case .redeem(let r): RewardPricing.coins(for: r)
        case .freeze(let day): freezeCost(day)
        }
    }

    /// Priced by level, with the monthly free one (`Perks`, `Redemption.freezeCost`).
    private func freezeCost(_ day: String) -> Int {
        Redemption.freezeCost(covering: day, level: Economy.level(ledger), ledger: ledger)
    }

    private func buy(_ c: Confirm) {
        do {
            switch c {
            case .redeem(let r): try Redemption.redeem(r, on: today, in: context)
            case .freeze: try Redemption.freeze(on: today, in: context)
            }
            actionError = nil
        } catch {
            actionError = "\(error)"
        }
        show(nil)
    }

    private func archive(_ r: Reward) {
        do { try Redemption.archive(r, in: context) } catch { actionError = "\(error)" }
    }

    private func toggleGoal(_ r: Reward) {
        do {
            if r.isGoal { try SavingsGoal.unpin(r, in: context) } else { try SavingsGoal.pin(r, in: context) }
        } catch {
            actionError = "\(error)"
        }
    }
}

/// A reward, or the streak freeze, as a card: a doodle disc, the name and its pills, the `⋯`
/// popover, and along the bottom why it can't be bought yet (clay, from `Purchase.Blocked`) beside
/// one `Redeem` pill. A blocked card is dimmed but keeps its price. The savings goal is the same
/// card with its progress bar.
private struct RewardCard: View {
    let doodle: DoodleKey
    let title: String
    let caption: String?
    let pills: [(text: String, style: PillLabel.Style)]
    let blocked: Purchase.Blocked?
    let buttonTitle: String
    let actions: [CardAction]
    let goal: SavingsGoal.Progress?
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var isOpen: Bool { blocked == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) { disc; details }
                    HStack(spacing: 0) { Spacer(minLength: 0); CardMenuButton(actions: actions) }
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    disc
                    details
                    CardMenuButton(actions: actions)
                }
            }
            if let goal { GoalBar(progress: goal) }
            bottom
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard(.surface, radius: LR.Radius.row)
        .overlay {
            if goal != nil {
                RoundedRectangle(cornerRadius: LR.Radius.row, style: .continuous)
                    .strokeBorder(LR.Color.ink, lineWidth: 2)
            }
        }
        .cardElement(label: title, value: spoken, complete: nil, actions: actions,
                     extra: isOpen ? [(title: buttonTitle, run: action)] : [])
    }

    private var disc: some View {
        Circle().fill(LR.Color.pillFill)
            .frame(width: 52, height: 52)
            .overlay { DoodleView(key: doodle, size: 28, tint: isOpen || goal != nil ? LR.Color.ink : LR.Color.iconNeutral) }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            if goal != nil {
                HandText("saving for", .hand).foregroundStyle(LR.Color.accent)
            }
            Text(title).lr(goal == nil ? .bodyStrong : .titleCard)
                .foregroundStyle(isOpen || goal != nil ? LR.Color.ink : LR.Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let caption {
                Text(caption).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !pills.isEmpty {
                FlowRow(spacing: 6) {
                    ForEach(Array(pills.enumerated()), id: \.offset) { _, pill in
                        PillLabel(text: pill.text, style: pill.style).monospacedDigit()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var bottom: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) { reason; Spacer(minLength: 0); button }
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 0) { reason; Spacer(minLength: 0) }
                button
            }
        }
    }

    /// Why it can't be bought. On the goal card a price still out of reach is already said by the
    /// bar's "N to go", so only the other reasons (debt, archived) are spelled out there.
    @ViewBuilder private var reason: some View {
        if let blocked, goal == nil || blocked.shortfall == nil {
            VStack(alignment: .leading, spacing: 2) {
                Text(blocked.cardReason).lr(.caption).foregroundStyle(LR.Color.clay)
                    .fixedSize(horizontal: false, vertical: true)
                if goal == nil, let short = blocked.shortfall {
                    Text("\(short) to go").lr(.caption).monospacedDigit()
                        .foregroundStyle(LR.Color.inkSecondary)
                }
            }
        }
    }

    private var button: some View {
        Button(buttonTitle, action: action)
            .buttonStyle(InkPillButtonStyle())
            .disabled(!isOpen)
    }

    private var spoken: String {
        let facts = pills.map(\.text) + [caption].compactMap { $0 }
        let status = blocked.map(\.cardReason) ?? "can be redeemed"
        let goalText = goal.map { ", saving goal, \($0.balance) of \($0.price) coins" } ?? ""
        return (facts + [status]).joined(separator: ", ") + goalText
    }
}

private extension Purchase.Blocked {
    /// The balance card already says the balance is negative, so a card under it only says what to do.
    var cardReason: String {
        if case .inDebt = self { return "Clear the debt first" }
        return description
    }
}

/// How far the balance is from the goal's price: a bar in the level card's own look and, under it,
/// what is left and the pace-based estimate. Both numbers are `SavingsGoal`'s.
private struct GoalBar: View {
    let progress: SavingsGoal.Progress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(LR.Color.dotEmpty)
                    Capsule().fill(LR.Color.fill).frame(width: proxy.size.width * progress.fraction)
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
            FlowRow(spacing: 8) {
                Text(progress.ready ? "Ready to redeem" : "\(progress.price - progress.balance) to go")
                    .lr(.bodyStrong).monospacedDigit().foregroundStyle(LR.Color.ink)
                if !progress.ready, let weeks = progress.weeksLeft {
                    Text("about \(weeks) week\(weeks == 1 ? "" : "s")")
                        .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                }
            }
        }
    }
}

/// Adding or editing a reward: a name and what it costs in real money. The coin price is never
/// typed in — it is shown as `RewardPricing` computes it, so two rewards can't drift apart.
private struct RewardEditor: View {
    let reward: Reward?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var cost: Double?
    @State private var isGoal = false
    /// The reward a first `Save` already inserted, so a retry after a failed pin doesn't add a second.
    @State private var created: Reward?
    @State private var error: String?

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && (cost ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LR.Spacing.sectionGap) {
                    SectionTitle(title: "Reward")
                    HStack(spacing: 12) {
                        Circle().fill(LR.Color.pillFill).frame(width: 52, height: 52)
                            .overlay { DoodleView(key: DoodleKey.forText(name), size: 28) }
                            .accessibilityHidden(true)
                        TextField("Name", text: $name, prompt: Text("Name").foregroundStyle(LR.Color.inkSecondary))
                            .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                            .submitLabel(.done)
                            .frame(minHeight: 44)
                    }
                    .modifier(FieldCard())

                    SectionTitle(title: "Estimated cost")
                    HStack(spacing: 12) {
                        TextField("Estimated cost", value: $cost, format: .number,
                                  prompt: Text("Estimated cost").foregroundStyle(LR.Color.inkSecondary))
                            .keyboardType(.decimalPad)
                            .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                            .frame(minHeight: 44)
                        if let cost, cost > 0 {
                            PillLabel(text: "\(RewardPricing.coins(estimatedCost: cost)) coins")
                                .monospacedDigit()
                        }
                    }
                    .modifier(FieldCard())
                    Text("What it costs in real money; the coin price follows from it.")
                        .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: $isGoal) {
                            Text("Saving for this").lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                        }
                        .tint(LR.Color.accent)
                        .frame(minHeight: 44)
                        Text("Today's level card tracks one reward at a time. Pinning this one unpins the other.")
                            .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .modifier(FieldCard())

                    if let error { BannerView(message: error) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                ConfirmBar(title: "Save", enabled: isValid) { save() }
            }
            .background(LR.Color.canvas.ignoresSafeArea())
            .navigationTitle(reward == nil ? "New reward" : "Edit reward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(LR.Color.ink)
                }
            }
            .onAppear {
                if let reward {
                    name = reward.name
                    cost = reward.estimatedCost
                    isGoal = reward.isGoal
                }
            }
        }
    }

    /// Repricing an existing reward only changes what it costs from now on; past redemptions
    /// keep what they were booked at in the ledger.
    private func save() {
        let r = reward ?? created ?? Reward()
        r.name = name.trimmingCharacters(in: .whitespaces)
        r.estimatedCost = cost ?? 0
        if reward == nil, created == nil {
            context.insert(r)
            created = r
        }
        do {
            try context.save()
            if isGoal != r.isGoal {
                if isGoal { try SavingsGoal.pin(r, in: context) } else { try SavingsGoal.unpin(r, in: context) }
            }
            dismiss()
        } catch {
            self.error = "\(error)"
        }
    }
}

/// The card frame of an editor field.
private struct FieldCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lrCard(.surface, radius: LR.Radius.row)
    }
}
