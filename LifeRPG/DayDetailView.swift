import LifeRPGCore
import SwiftData
import SwiftUI

/// One day, as it happened (`PLAN.md` §9). Read-only: everything here is history.
struct DayDetailView: View {
    let dayKey: String

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch Result(catching: { try DayRecord.load(dayKey, in: context) }) {
                case .success(let record): content(record)
                case .failure(let error): Text(error.localizedDescription).foregroundStyle(.red).padding()
                }
            }
            .navigationTitle(dayKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func content(_ record: DayRecord) -> some View {
        List {
            Section {
                LabeledContent("Net points") { points(record.netPoints) }
            }

            if let c = record.context { bodySection(c) }

            if !record.routines.isEmpty {
                Section("Routines due") {
                    ForEach(record.routines) { routineRow($0) }
                }
            }
            if !record.completedForOtherDays.isEmpty {
                Section("Done this day for another day") {
                    ForEach(record.completedForOtherDays) { routineRow($0, showDue: true) }
                }
            }

            Section("Quests") {
                if record.quests.isEmpty {
                    Text("No quests this day").foregroundStyle(.secondary)
                }
                ForEach(record.quests) { questRow($0) }
            }

            if !record.otherLedger.isEmpty {
                Section("Spending, penalties, skips") {
                    ForEach(record.otherLedger) { e in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.kind.capitalized)
                                if !e.note.isEmpty {
                                    Text(e.note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            points(e.points)
                        }
                    }
                }
            }

            if !record.otherRatings.isEmpty {
                Section("Other ratings this day") {
                    ForEach(record.otherRatings) { r in
                        HStack { Text(r.textSnapshot); Spacer(); rating(r.rating) }
                    }
                }
            }
        }
    }

    private func bodySection(_ c: DailyContext) -> some View {
        Section("Body") {
            LabeledContent("Tier", value: c.tier.rawValue + cycleNote(c))
            LabeledContent("Readiness", value: "\(c.readiness)")
            LabeledContent("Energy", value: c.energy.formatted(.number.precision(.fractionLength(3))))
            LabeledContent("HRV", value: c.hrv.map { "\(Int($0.rounded())) ms" } ?? "—")
            LabeledContent("Sleep", value: c.sleepHours.map { $0.formatted(.number.precision(.fractionLength(1))) + " h" } ?? "—")
            LabeledContent("Resting HR", value: c.restingHR.map { "\(Int($0.rounded())) bpm" } ?? "—")
            LabeledContent("Routine load · random slots", value: "\(c.routineLoad) · \(c.randomSlots)")
        }
    }

    /// Days 1–3 are why the tier reads `low` on a day the body data alone would have called
    /// normal, so the day detail says which day it was.
    private func cycleNote(_ c: DailyContext) -> String {
        if let day = c.cycleDay { return " · cycle day \(day)" }
        return c.onCycle ? " · cycle" : ""
    }

    private func questRow(_ line: DayRecord.QuestLine) -> some View {
        let q = line.quest
        return HStack(alignment: .firstTextBaseline) {
            Text(q.isHiddenSlot ? "★" : q.slot.code)
                .font(.caption.weight(.bold)).frame(minWidth: 28)
                .foregroundStyle(q.isHiddenSlot ? .yellow : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                if q.isTrivialGroup {
                    ForEach(q.trivialGroup.indices, id: \.self) { i in
                        let done = q.trivialDone.indices.contains(i) && q.trivialDone[i]
                        HStack(spacing: 6) {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(done ? .green : .secondary)
                            Text(q.trivialGroup[i])
                        }
                    }
                } else {
                    Text([q.textSnapshot, q.variantSnapshot].compactMap { $0 }.filter { !$0.isEmpty }
                        .joined(separator: " — "))
                        .strikethrough(q.replaced)
                }
                Text(questStatus(q)).font(.caption).foregroundStyle(.secondary)
                ForEach(line.ratings) { r in
                    HStack(spacing: 4) { Text("Rated").font(.caption).foregroundStyle(.secondary); rating(r.rating) }
                }
            }
            Spacer()
            if let p = q.points { points(p) }
        }
    }

    private func questStatus(_ q: DailyQuest) -> String {
        if q.replaced { return "Replaced by an ad-hoc routine" }
        var parts: [String] = []
        if let at = q.completedAt { parts.append("Done \(at.formatted(date: .omitted, time: .shortened))") }
        else { parts.append("Not done") }
        if q.sourceTypeRaw == SourceType.healthKit.rawValue { parts.append("auto-verified") }
        if q.rerollCount > 0 { parts.append("rerolled \(q.rerollCount)×") }
        return parts.joined(separator: " · ")
    }

    private func routineRow(_ line: DayRecord.RoutineLine, showDue: Bool = false) -> some View {
        let o = line.occurrence
        return HStack(alignment: .firstTextBaseline) {
            Text("R").font(.caption.weight(.bold)).frame(minWidth: 28).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(o.displayText)
                Text(routineStatus(line, showDue: showDue)).font(.caption).foregroundStyle(.secondary)
                ForEach(line.ratings) { r in
                    HStack(spacing: 4) { Text("Rated").font(.caption).foregroundStyle(.secondary); rating(r.rating) }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let p = o.awardedPoints { points(p) }
                if o.penaltyApplied > 0 { points(-o.penaltyApplied).font(.caption) }
            }
        }
    }

    private func routineStatus(_ line: DayRecord.RoutineLine, showDue: Bool) -> String {
        let o = line.occurrence
        var parts: [String] = []
        switch line.status {
        case .done: parts.append("Done")
        case .doneAhead(let on): parts.append("Done ahead on \(on)")
        case .late(let on): parts.append("Made up late on \(on)")
        case .skipped: parts.append("Skipped")
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

    private func points(_ p: Int) -> some View {
        Text(p > 0 ? "+\(p)" : "\(p)")
            .monospacedDigit()
            .foregroundStyle(p > 0 ? .green : p < 0 ? .red : .secondary)
    }

    private func rating(_ r: Int) -> some View {
        Text(r > 0 ? "+\(r)" : "\(r)")
            .font(.caption.weight(.semibold)).monospacedDigit()
            .foregroundStyle(r > 0 ? .green : r < 0 ? .red : .secondary)
    }
}
