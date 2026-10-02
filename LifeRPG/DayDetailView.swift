import LifeRPGCore
import SwiftData
import SwiftUI

/// One day, as it happened (`PLAN.md` §9). Read-only: everything here is history. Cards on the
/// canvas, with quests and routines in the same row frame as Today's, minus the controls.
struct DayDetailView: View {
    let dayKey: String

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch Result(catching: { try DayRecord.load(dayKey, in: context) }) {
                case .success(let record): content(record)
                case .failure(let error):
                    BannerView(message: error.localizedDescription).padding(16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(LR.Color.canvas.ignoresSafeArea())
            .navigationTitle(friendlyDate)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(LR.Color.ink)
                }
            }
        }
    }

    /// `Friday, October 2`; the `dayKey` itself is on the summary card, so VoiceOver and the eye
    /// both still have it.
    private var friendlyDate: String {
        DayKey.date(dayKey).map { $0.formatted(.dateTime.weekday(.wide).month(.wide).day()) } ?? dayKey
    }

    private func content(_ record: DayRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LR.Spacing.sectionGap) {
                summaryCard(record.netPoints)

                if let c = record.context { bodyCard(c) }

                if !record.routines.isEmpty {
                    section("Routines due") {
                        ForEach(record.routines) { routineRow($0) }
                    }
                }
                if !record.completedForOtherDays.isEmpty {
                    section("Done this day for another day") {
                        ForEach(record.completedForOtherDays) { routineRow($0, showDue: true) }
                    }
                }

                section("Quests") {
                    if record.quests.isEmpty {
                        RecordRowView(title: "No quests this day", secondary: true) { EmptyView() }
                    }
                    ForEach(record.quests) { questRow($0) }
                }

                if !record.otherLedger.isEmpty {
                    section("Spending, penalties, skips") {
                        plainCard {
                            ForEach(Array(record.otherLedger.enumerated()), id: \.element.id) { index, e in
                                if index > 0 { divider }
                                ledgerRow(e)
                            }
                        }
                    }
                }

                if !record.otherRatings.isEmpty {
                    section("Other ratings this day") {
                        plainCard {
                            ForEach(Array(record.otherRatings.enumerated()), id: \.element.id) { index, r in
                                if index > 0 { divider }
                                ratingRow(r)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: title)
            rows()
        }
    }

    private var divider: some View {
        Rectangle().fill(LR.Color.divider).frame(height: 1)
    }

    private func plainCard<Content: View>(@ViewBuilder _ rows: () -> Content) -> some View {
        VStack(spacing: 0) { rows() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lrCard(.surface, radius: LR.Radius.row)
    }

    // MARK: summary and body

    private func summaryCard(_ net: Int) -> some View {
        let text = net > 0 ? "+\(net)" : "\(net)"
        return HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Net points").lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                // Sage fails contrast as text on a white card, so a gain stays `ink` and the sign
                // says which way it went; a loss is clay.
                Text(text).lr(.handDisplay).monospacedDigit()
                    .foregroundStyle(net < 0 ? LR.Color.clay : net == 0 ? LR.Color.inkSecondary : LR.Color.ink)
            }
            Spacer(minLength: 8)
            Text(dayKey).lr(.caption).monospacedDigit().foregroundStyle(LR.Color.inkSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard(.surface, radius: LR.Radius.card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(dayKey), net points")
        .accessibilityValue("\(text) coins")
    }

    private func bodyCard(_ c: DailyContext) -> some View {
        let facts: [(label: String, value: String)] = [
            ("Readiness", "\(c.readiness)"),
            ("Energy", c.energy.formatted(.number.precision(.fractionLength(3)))),
            ("HRV", c.hrv.map { "\(Int($0.rounded())) ms" } ?? "—"),
            ("Sleep", c.sleepHours.map { $0.formatted(.number.precision(.fractionLength(1))) + " h" } ?? "—"),
            ("Resting HR", c.restingHR.map { "\(Int($0.rounded())) bpm" } ?? "—"),
        ]
        return section("Body") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Tier").lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                    PillLabel(text: c.tier.rawValue)
                    if let note = cycleNote(c) { PillLabel(text: note) }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .topLeading)],
                          alignment: .leading, spacing: 12) {
                    ForEach(facts, id: \.label) { fact in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fact.label).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                            Text(fact.value).lr(.bodyStrong).monospacedDigit().foregroundStyle(LR.Color.ink)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Routine load · random slots").lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                    Text("\(c.routineLoad) · \(c.randomSlots)").lr(.bodyStrong).monospacedDigit()
                        .foregroundStyle(LR.Color.ink)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lrCard(.surface, radius: LR.Radius.card)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Body, tier \(c.tier.rawValue)" + (cycleNote(c).map { ", \($0)" } ?? ""))
            .accessibilityValue((facts.map { "\($0.label) \($0.value)" }
                + ["Routine load, random slots \(c.routineLoad), \(c.randomSlots)"]).joined(separator: ", "))
        }
    }

    /// Days 1–3 are why the tier reads `low` on a day the body data alone would have called
    /// normal, so the day detail says which day it was.
    private func cycleNote(_ c: DailyContext) -> String? {
        if let day = c.cycleDay { return "cycle day \(day)" }
        return c.onCycle ? "cycle" : nil
    }

    // MARK: quests

    private func questRow(_ line: DayRecord.QuestLine) -> some View {
        let q = line.quest
        let tint: QuestTint? = q.replaced || q.slot == .epic ? nil
            : q.isHiddenSlot ? .hidden : q.isTrivialGroup ? .trivial : QuestTint(q.slot)
        let slotName = q.isHiddenSlot ? "hidden" : q.slot.rawValue
        let title = q.isTrivialGroup
            ? "Micro-actions"
            : [q.textSnapshot, q.variantSnapshot].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
        let status = questStatus(q)
        let spokenTitle = q.isTrivialGroup ? q.trivialGroup.joined(separator: ", ") : title

        var pills = [PillState(slotName, .plain)]
        if let p = q.points { pills.append(pointPill(p)) }
        pills += line.ratings.map(ratingPill)

        return HistoryRowView(
            doodle: q.slot == .epic ? .flag : q.isTrivialGroup ? .sparkle : DoodleKey.forText(q.textSnapshot),
            fill: tint.map(CardFill.tint) ?? .surface,
            title: title,
            dropped: q.replaced,
            items: q.trivialGroup.indices.map { i in
                (q.trivialGroup[i], q.trivialDone.indices.contains(i) && q.trivialDone[i])
            },
            status: status,
            pills: pills,
            mark: q.replaced ? .dropped : q.completedAt != nil ? .done : .open,
            accessibilityLabel: "\(spokenTitle), \(slotName) quest",
            accessibilityValue: ([status] + [q.points.map { "\($0) coins" }].compactMap { $0 }
                + line.ratings.map { "rated \($0.rating)" }).joined(separator: ", "))
    }

    private func questStatus(_ q: DailyQuest) -> String {
        if q.replaced {
            switch q.replacedReason {
            case .replan: return "Dropped when the day was re-planned"
            case .rerolled: return "Rerolled away"
            case .cancelled: return "Cancelled"
            case .adHoc: return "Replaced by an ad-hoc routine"
            case .swapped: return "Swapped for a hand-picked epic"
            }
        }
        var parts: [String] = []
        if let at = q.completedAt { parts.append("Done \(at.formatted(date: .omitted, time: .shortened))") }
        else { parts.append("Not done") }
        if q.sourceTypeRaw == SourceType.healthKit.rawValue { parts.append("auto-verified") }
        if q.rerollCount > 0 { parts.append("rerolled \(q.rerollCount)×") }
        return parts.joined(separator: " · ")
    }

    // MARK: routines

    private func routineRow(_ line: DayRecord.RoutineLine, showDue: Bool = false) -> some View {
        let o = line.occurrence
        let status = routineStatus(line, showDue: showDue)

        var pills: [PillState] = []
        if let p = o.awardedPoints { pills.append(pointPill(p)) }
        if o.penaltyApplied > 0 { pills.append(PillState("-\(o.penaltyApplied)", .clay)) }
        pills += line.ratings.map(ratingPill)

        let mark: HistoryMark.Kind = switch line.status {
        case .done, .doneAhead, .late: .done
        case .skipped, .replaced: .dropped
        case .notDone: .open
        }
        var spoken = [status]
        if let p = o.awardedPoints { spoken.append("\(p) coins") }
        if o.penaltyApplied > 0 { spoken.append("penalty \(o.penaltyApplied) coins") }
        spoken += line.ratings.map { "rated \($0.rating)" }

        return HistoryRowView(
            doodle: DoodleKey.forText(o.displayText),
            title: o.displayText,
            dropped: line.status == .replaced,
            status: status,
            pills: pills,
            mark: mark,
            accessibilityLabel: "\(o.displayText), routine",
            accessibilityValue: spoken.joined(separator: ", "))
    }

    private func routineStatus(_ line: DayRecord.RoutineLine, showDue: Bool) -> String {
        let o = line.occurrence
        var parts: [String] = []
        switch line.status {
        case .done: parts.append("Done")
        case .doneAhead(let on): parts.append("Done ahead on \(on)")
        // Timing only; the points beside it say whether it paid half (a make-up) or full.
        case .late(let on): parts.append("Done on \(on)")
        case .skipped: parts.append("Skipped")
        case .replaced: parts.append("Replaced by an ad-hoc routine")
        case .notDone: parts.append("Not done")
        }
        if let at = o.completedAt { parts.append(at.formatted(date: .omitted, time: .shortened)) }
        if showDue { parts.append("due \(o.dueDayKey)") }
        if o.usedDegraded { parts.append("light version") }
        if o.sourceTypeRaw == SourceType.healthKit.rawValue { parts.append("auto-verified") }
        if o.replacesQuestID != nil { parts.append("ad-hoc") }
        if !o.countsForClear { parts.append("doesn't gate the day") }
        return parts.joined(separator: " · ")
    }

    // MARK: ledger and ratings

    private func ledgerRow(_ e: LedgerEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.kind.capitalized).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                if !e.note.isEmpty {
                    Text(e.note).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            pointsPill(e.points)
        }
        .padding(14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(e.kind.capitalized + (e.note.isEmpty ? "" : ", \(e.note)"))
        .accessibilityValue("\(e.points) coins")
    }

    private func ratingRow(_ r: QuestRating) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(r.textSnapshot).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            PillLabel(text: signed(r.rating), style: r.rating < 0 ? .clay : .plain)
        }
        .padding(14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(r.textSnapshot)
        .accessibilityValue("rated \(r.rating)")
    }

    // MARK: small pieces

    private func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : "\(n)" }

    private func pointPill(_ p: Int) -> PillState { PillState(signed(p), p < 0 ? .clay : .payout) }

    private func ratingPill(_ r: QuestRating) -> PillState {
        PillState("Rated \(signed(r.rating))", r.rating < 0 ? .clay : .plain)
    }

    private func pointsPill(_ p: Int) -> some View {
        PillLabel(text: signed(p), style: p < 0 ? .clay : .plain)
    }
}
