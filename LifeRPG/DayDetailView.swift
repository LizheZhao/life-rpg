import LifeRPGCore
import SwiftData
import SwiftUI

/// The calendar's day sheet (`PLAN.md` §9): the date and what the day paid, the routines and the
/// quests as collapsible sections, and the night's entry (or the way to write one). Read-only apart
/// from that link. Every number, tag and rule (done / total, the header, when the sheet opens) is
/// `DaySheet` in Core.
struct DayDetailView: View {
    let dayKey: String
    /// The app's day, which decides whether this day can still be written about.
    let today: String
    /// Which sections are open, held by the calendar so it lasts for the session.
    @Binding var sections: DaySheet.Sections

    @Environment(\.modelContext) private var context

    var body: some View {
        DayDetailPage(dayKey: dayKey, today: today, sections: $sections, context: context)
    }
}

/// A sheet that is 720 pt tall, or as tall as the screen allows.
struct DaySheetDetent: CustomPresentationDetent {
    static let height: CGFloat = 720

    static func height(in context: Context) -> CGFloat? { min(height, context.maxDetentValue) }
}

private struct DayDetailPage: View {
    let dayKey: String
    let today: String
    @Binding var sections: DaySheet.Sections

    /// Read once, before the first frame, so toggling a section does not fetch the day again.
    @State private var record: Result<DayRecord, Error>
    /// That day's entry row, if it has one.
    @Query private var journalEntries: [JournalEntry]
    @State private var presented: Presented?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Presented: Identifiable {
        case read, write

        var id: Self { self }
    }

    /// Characters of the entry the night card shows: about three lines at the card's width.
    private static let excerptLength = 120

    init(dayKey: String, today: String, sections: Binding<DaySheet.Sections>, context: ModelContext) {
        self.dayKey = dayKey
        self.today = today
        _sections = sections
        _record = State(initialValue: Result { try DayRecord.load(dayKey, in: context) })
        _journalEntries = Query(filter: #Predicate<JournalEntry> { $0.dayKey == dayKey })
    }

    var body: some View {
        Group {
            switch record {
            case .success(let record): content(record)
            case .failure(let error): BannerView(message: error.localizedDescription).padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LR.Color.canvas.ignoresSafeArea())
        .fullScreenCover(item: $presented) { target in
            switch target {
            case .read: JournalReadingView(startDay: dayKey)
            case .write: JournalEditorView(dayKey: dayKey, today: today)
            }
        }
    }

    private func content(_ record: DayRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LR.Spacing.sectionGap) {
                header(record)

                if !record.routines.isEmpty {
                    collapsible("Routines", progress: DaySheet.routineProgress(record.routines),
                                open: sections.routinesOpen) { toggle(.routines) } rows: {
                        ForEach(record.routines) { routineRow($0) }
                    }
                }
                if !record.quests.isEmpty {
                    collapsible("Quests", progress: DaySheet.questProgress(record.quests),
                                open: sections.questsOpen) { toggle(.quests) } rows: {
                        ForEach(record.quests) { questRow($0) }
                    }
                }

                if let night = JournalEntryHistory.days(from: journalEntries).first {
                    nightCard(night)
                } else {
                    nothingWritten
                }

                if !record.completedForOtherDays.isEmpty {
                    section("Done this day for another day") {
                        ForEach(record.completedForOtherDays) { routineRow($0, showDue: true) }
                    }
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
                    // Both sources of `DayRecord.otherRatings`: a Library rating has no completion
                    // to attach to, and a late `Rate / note` hangs off an earlier day's card.
                    section("Other ratings this day", caption: "Ratings given this day.") {
                        plainCard {
                            ForEach(Array(record.otherRatings.enumerated()), id: \.element.id) { index, r in
                                if index > 0 { divider }
                                ratingRow(r)
                            }
                        }
                    }
                }

                if let c = record.context { bodyCard(c) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
    }

    private func toggle(_ section: DaySheet.Section) {
        Haptics.selection()
        withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.22)) { sections.toggle(section) }
    }

    // MARK: header and sections

    private func header(_ record: DayRecord) -> some View {
        let header = DaySheet.header(dayKey: dayKey, net: record.netPoints, tier: record.context?.tier)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 8) {
                headerDate(header)
                Spacer(minLength: 8)
                HStack(spacing: 6) { headerTags(header) }
            }
            VStack(alignment: .leading, spacing: 8) {
                headerDate(header)
                HStack(spacing: 6) { headerTags(header) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(header.weekday), \(header.date)")
        .accessibilityValue([header.coins, header.dayType].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isHeader)
    }

    private func headerDate(_ header: DaySheet.Header) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HandText(header.weekday, .hand).foregroundStyle(LR.Color.trendDeep)
            Text(header.date).lr(.statNumber).foregroundStyle(LR.Color.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder private func headerTags(_ header: DaySheet.Header) -> some View {
        PillLabel(text: header.coins)
        if let dayType = header.dayType { PillLabel(text: dayType) }
    }

    /// A title row with `done / total` and a chevron; the whole row toggles the rows under it.
    private func collapsible<Rows: View>(_ title: String, progress: DaySheet.Progress, open: Bool,
                                         toggle: @escaping () -> Void,
                                         @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggle) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title).lr(.titleCard).foregroundStyle(LR.Color.ink)
                    Spacer(minLength: 8)
                    HandText(progress.text, .hand).foregroundStyle(LR.Color.trendDeep)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LR.Color.iconNeutral)
                        .rotationEffect(.degrees(open ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(progress.text)")
            .accessibilityHint(open ? "Hides them" : "Shows them")
            .accessibilityAddTraits(.isHeader)
            if open {
                VStack(spacing: 8) { rows() }
                    .transition(.opacity)
            }
        }
    }

    private func section<Content: View>(_ title: String, caption: String? = nil,
                                        @ViewBuilder _ rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: title)
            if let caption {
                Text(caption).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    // MARK: body

    private func bodyCard(_ c: DailyContext) -> some View {
        let facts: [(label: String, value: String)] = [
            ("Readiness", "\(c.readiness)"),
            ("Energy", c.energy.formatted(.number.precision(.fractionLength(2)))),
            ("HRV", c.hrv.map { "\(Int($0.rounded())) ms" } ?? "—"),
            ("Sleep", c.sleepHours.map { $0.formatted(.number.precision(.fractionLength(1))) + " h" } ?? "—"),
            ("Resting HR", c.restingHR.map { "\(Int($0.rounded())) bpm" } ?? "—"),
        ]
        return section("Body") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    PillLabel(text: c.tier.dayText)
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
                    Text("Routines · quests").lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                    Text("\(c.routineLoad) · \(c.randomSlots)").lr(.bodyStrong).monospacedDigit()
                        .foregroundStyle(LR.Color.ink)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lrCard(.surface, radius: LR.Radius.card)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Body, \(c.tier.dayText)" + (cycleNote(c).map { ", \($0)" } ?? ""))
            .accessibilityValue((facts.map { "\($0.label) \($0.value)" }
                + ["Routines \(c.routineLoad), quests \(c.randomSlots)"]).joined(separator: ", "))
        }
    }

    /// Days 1–3 are why the tier reads `low` on a day the body data alone would have called
    /// normal, so the day detail says which day it was.
    private func cycleNote(_ c: DailyContext) -> String? {
        if let day = c.cycleDay { return "cycle day \(day)" }
        return c.onCycle ? "cycle" : nil
    }

    // MARK: that night

    private func nightCard(_ day: JournalEntryDay) -> some View {
        let when = day.writtenAt.formatted(date: .omitted, time: .shortened)
        let words = JournalPageText.words(day.wordCount)
        let excerpt = day.excerpt(limit: Self.excerptLength)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("THAT NIGHT").lr(.pill).tracking(1.2).foregroundStyle(LR.Color.sectionTitle)
                Spacer(minLength: 8)
                Text("\(when) \u{00B7} \(words)").lr(.caption).monospacedDigit().foregroundStyle(LR.Color.sectionTitle)
            }
            // The card below says all of it.
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 14) {
                Text(excerpt).lr(.journalExcerpt)
                    .foregroundStyle(LR.Color.onNight)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("That night, \(when), \(words). \(excerpt)")
                HStack(spacing: 10) {
                    nightAction("Read", systemImage: "book", hint: "Opens the whole entry to read") { presented = .read }
                    nightAction("Edit", systemImage: "pencil", hint: "Opens the entry to edit") { presented = .write }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: LR.Radius.row, style: .continuous).fill(LR.Color.nightCard))
        }
    }

    private func nightAction(_ title: String, systemImage: String, hint: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 14, weight: .semibold)).accessibilityHidden(true)
                Text(title).lr(.bodyStrong)
            }
            .foregroundStyle(LR.Color.nightAccent)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Capsule().strokeBorder(LR.Color.nightAccent.opacity(0.6), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityHint(hint)
    }

    /// No entry that day: a flat outline in place of the dark card, and the way to write one unless
    /// the day has not happened yet.
    private var nothingWritten: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("THAT NIGHT").lr(.pill).tracking(1.2).foregroundStyle(LR.Color.sectionTitle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(DaySheet.nothingWrittenTitle).lr(.bodyStrong).foregroundStyle(LR.Color.inkSecondary)
                if DaySheet.canWrite(dayKey: dayKey, today: today) {
                    Button { presented = .write } label: {
                        HStack(spacing: 6) {
                            Text(DaySheet.writeLinkTitle).lr(.bodyStrong)
                            Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold))
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(LR.Color.trendDeep)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: LR.Radius.row, style: .continuous)
                .strokeBorder(LR.Color.dotEmpty, lineWidth: 1.5))
        }
    }

    // MARK: quests

    private func questRow(_ line: DayRecord.QuestLine) -> some View {
        let q = line.quest
        let tint: QuestTint? = q.replaced ? nil
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
            mark: historyMark(RecordMark.mark(for: q)),
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
        if o.usedDegraded { pills.append(PillState("light version", .plain)) }
        if o.penaltyApplied > 0 { pills.append(PillState("-\(o.penaltyApplied)", .clay)) }
        pills += line.ratings.map(ratingPill)

        var spoken = [status]
        if let p = o.awardedPoints { spoken.append("\(p) coins") }
        if o.usedDegraded { spoken.append("light version") }
        if o.penaltyApplied > 0 { spoken.append("penalty \(o.penaltyApplied) coins") }
        spoken += line.ratings.map { "rated \($0.rating)" }

        return HistoryRowView(
            doodle: o.doodle,
            fill: line.status == .replaced ? .surface : .tint(.routine),
            title: o.displayText,
            dropped: line.status == .replaced,
            status: status,
            pills: pills,
            mark: historyMark(RecordMark.mark(for: line.status)),
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
        case .missed: parts.append("Did not finish")
        case .replaced: parts.append("Replaced by an ad-hoc routine")
        case .notDone: parts.append("Not done")
        }
        if let at = o.completedAt { parts.append(at.formatted(date: .omitted, time: .shortened)) }
        if showDue { parts.append("due \(o.dueDayKey)") }
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

    private func historyMark(_ mark: RecordMark) -> HistoryMark.Kind {
        switch mark {
        case .done: .done
        case .open: .open
        case .dashed: .dropped
        case .crossed: .missed
        }
    }

    private func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : "\(n)" }

    private func pointPill(_ p: Int) -> PillState { PillState(signed(p), p < 0 ? .clay : .payout) }

    private func ratingPill(_ r: QuestRating) -> PillState {
        PillState("Rated \(signed(r.rating))", r.rating < 0 ? .clay : .plain)
    }

    private func pointsPill(_ p: Int) -> some View {
        PillLabel(text: signed(p), style: p < 0 ? .clay : .plain)
    }
}
