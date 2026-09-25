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

    @Environment(\.modelContext) private var context
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

    private enum Confirm {
        case redeem(Reward)
        case freeze(String)
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
            List {
                if let actionError {
                    Section { Text(actionError).foregroundStyle(.red) }
                }

                Section {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(balance)")
                            .font(.largeTitle.monospacedDigit().bold())
                            .foregroundStyle(balance < 0 ? .red : .primary)
                        Text("coins").font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let repairable { freezeSection(repairable) }

                Section("Rewards") {
                    if active.isEmpty {
                        Text("Nothing here yet. Tap + to add something worth saving for.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(active) { rewardRow($0) }
                }

                if !redeemed.isEmpty {
                    Section("Redeemed") {
                        ForEach(redeemed.prefix(30)) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.note)
                                    Text(entry.dayKey).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(entry.points)").monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Rewards")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = Editing(reward: nil) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add a reward")
                }
            }
            .sheet(item: $editing) { e in
                RewardEditor(reward: e.reward)
            }
            .alert(title(for: confirming),
                   isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                   presenting: confirming) { c in
                Button("Spend \(cost(of: c))") { buy(c) }
                Button("Keep coins", role: .cancel) {}
            } message: { c in
                switch c {
                case .redeem(let r):
                    Text("\(r.name)\n\n\(cost(of: c)) coins. This is final.")
                case .freeze(let day):
                    Text("Cover \(day) so the streak doesn't break there. \(cost(of: c)) coins.")
                }
            }
        }
    }

    // MARK: rows

    private func freezeSection(_ day: String) -> some View {
        let blocked = Redemption.blockedFreeze(days: completedDays, frozen: frozenDays,
                                               today: today, balance: balance)
        return Section("Streak") {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Missed \(day)")
                    Text("A freeze covers it, and the streak runs on as if it hadn't broken.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Freeze · \(Redemption.streakFreezeCost)") { confirming = .freeze(day) }
                    .buttonStyle(.bordered)
                    .disabled(blocked != nil)
            }
        }
    }

    private func rewardRow(_ r: Reward) -> some View {
        let coins = RewardPricing.coins(for: r)
        let open = Redemption.blocked(redeeming: r, balance: balance) == nil
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name)
                Text("≈ \(r.estimatedCost.formatted()) · \(coins) coins")
                    .font(.caption).foregroundStyle(.secondary)
                // How far off it is, so the list doubles as a savings tracker.
                if !open, balance >= 0, coins > balance {
                    Text("\(coins - balance) to go").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button("Redeem") { confirming = .redeem(r) }
                .buttonStyle(.bordered)
                .disabled(!open)
        }
        .swipeActions(edge: .trailing) {
            // Archived, never deleted: past redemptions still point at it.
            Button { archive(r) } label: { Label("Archive", systemImage: "archivebox") }
                .tint(.gray)
            Button { editing = Editing(reward: r) } label: { Label("Edit", systemImage: "pencil") }
                .tint(.blue)
        }
    }

    // MARK: actions

    private func title(for c: Confirm?) -> String {
        switch c {
        case .redeem: "Redeem?"
        case .freeze: "Buy a streak freeze?"
        case nil: ""
        }
    }

    private func cost(of c: Confirm) -> Int {
        switch c {
        case .redeem(let r): RewardPricing.coins(for: r)
        case .freeze: Redemption.streakFreezeCost
        }
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
        confirming = nil
    }

    private func archive(_ r: Reward) {
        r.isActive = false
        do { try context.save() } catch { actionError = "\(error)" }
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
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Estimated cost", value: $cost, format: .number)
                        .keyboardType(.decimalPad)
                } footer: {
                    if let cost, cost > 0 {
                        Text("\(RewardPricing.coins(estimatedCost: cost)) coins")
                    } else {
                        Text("What it costs in real money; the coin price follows from it.")
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(reward == nil ? "New reward" : "Edit reward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (cost ?? 0) <= 0)
                }
            }
            .onAppear {
                if let reward {
                    name = reward.name
                    cost = reward.estimatedCost
                }
            }
        }
    }

    /// Repricing an existing reward only changes what it costs from now on; past redemptions
    /// keep what they were booked at in the ledger.
    private func save() {
        let r = reward ?? Reward()
        r.name = name.trimmingCharacters(in: .whitespaces)
        r.estimatedCost = cost ?? 0
        if reward == nil { context.insert(r) }
        do {
            try context.save()
            dismiss()
        } catch {
            self.error = "\(error)"
        }
    }
}
