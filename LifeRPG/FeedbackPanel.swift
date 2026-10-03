import LifeRPGCore
import SwiftData
import SwiftUI

/// Rate it again, or leave a note — for one quest or routine, wherever it is reached from: the
/// Library page, and the `⋯` menu on a Today card (`FeedbackSheet`). Both only ever append, so a
/// changed opinion is a new row and the old ones stay.
struct FeedbackPanel: View {
    let target: FeedbackTarget
    /// The `QuestTemplate` or `RoutineTask` the feedback is filed under.
    let id: UUID
    let text: String
    /// The one completion the feedback links back to when it is given from a card; nil from the
    /// Library, which has no completion to point at.
    var questID: UUID?
    let today: String

    @Environment(\.modelContext) private var context
    @Query private var ratings: [QuestRating]
    @Query private var comments: [QuestComment]

    @State private var note = ""
    @State private var error: String?

    private var history: [QuestRating] { Feedback.ratings(ratings, for: id) }
    private var notes: [QuestComment] { Feedback.comments(comments, for: id) }
    private var canAddNote: Bool { !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: LR.Spacing.sectionGap) {
            ratingSection
            noteSection
            if let error { BannerView(message: error) }
            if !notes.isEmpty { notesSection }
            if !history.isEmpty { ratingsSection }
        }
    }

    // MARK: pieces

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lrCard(.surface, radius: LR.Radius.row)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: title)
            content()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
    }

    private var divider: some View {
        Rectangle().fill(LR.Color.divider).frame(height: 1)
    }

    // MARK: rating

    private var ratingSection: some View {
        section("How do you feel about it now?") {
            card {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { ratingButtons }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ratingButtons
                    }
                }
            }
            if let last = history.first {
                caption("Latest: \(label(last.rating)), \(last.dayKey). Rating again adds a new entry; the old ones stay.")
            } else {
                caption("Not rated yet.")
            }
        }
    }

    private var ratingButtons: some View {
        ForEach(RatingScale.steps, id: \.value) { step in
            let selected = history.first?.rating == step.value
            Button {
                Haptics.selection()
                rate(step.value)
            } label: {
                Image(systemName: step.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(selected ? LR.Color.onFill : LR.Color.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(selected ? LR.Color.fill : LR.Color.pillFill))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityLabel(step.label)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }

    // MARK: notes

    private var noteSection: some View {
        section("Add a note") {
            card {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("What worked, what didn't", text: $note,
                              prompt: Text("What worked, what didn't").foregroundStyle(LR.Color.inkSecondary),
                              axis: .vertical)
                        .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                        .frame(minHeight: 44, alignment: .topLeading)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Button("Add note") { addNote() }
                            .buttonStyle(PillButtonStyle())
                            .disabled(!canAddNote)
                            .opacity(canAddNote ? 1 : 0.4)
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        section("Notes") {
            VStack(spacing: 0) {
                ForEach(Array(notes.enumerated()), id: \.element.id) { index, c in
                    if index > 0 { divider }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.comment).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(c.dayKey).lr(.caption).monospacedDigit().foregroundStyle(LR.Color.inkSecondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(c.comment)
                    .accessibilityValue(c.dayKey)
                }
            }
            .lrCard(.surface, radius: LR.Radius.row)
        }
    }

    private var ratingsSection: some View {
        section("Ratings") {
            VStack(spacing: 0) {
                ForEach(Array(history.enumerated()), id: \.element.id) { index, r in
                    if index > 0 { divider }
                    let when = r.questID == nil ? r.dayKey : "\(r.dayKey) · right after doing it"
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label(r.rating)).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                            Text(when).lr(.caption).monospacedDigit().foregroundStyle(LR.Color.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        RatingBadge(value: r.rating)
                    }
                    .padding(12)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label(r.rating))
                    .accessibilityValue(when)
                }
            }
            .lrCard(.surface, radius: LR.Radius.row)
        }
    }

    // MARK: actions

    private func label(_ value: Int) -> String {
        RatingScale.label(for: value)
    }

    private func rate(_ value: Int) {
        Feedback.rate(context, target: target, id: id, questID: questID, text: text,
                      rating: value, dayKey: today)
        try? Affinity.sync(context)           // the next draw already weighs it
        save()
    }

    private func addNote() {
        Feedback.comment(context, target: target, id: id, questID: questID, text: text,
                         comment: note.trimmingCharacters(in: .whitespacesAndNewlines), dayKey: today)
        if save() { note = "" }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try context.save()
            error = nil
            return true
        } catch {
            self.error = "\(error)"
            return false
        }
    }
}

/// The card's `⋯ → Rate / note`: the same panel, in a sheet, for the thing on the card.
struct FeedbackSheet: View {
    let subject: Feedback.Subject
    let today: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LR.Spacing.sectionGap) {
                    Text(subject.text).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lrCard(.surface, radius: LR.Radius.row)
                    FeedbackPanel(target: subject.target, id: subject.id, text: subject.text,
                                  questID: subject.instanceID, today: today)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(LR.Color.canvas.ignoresSafeArea())
            .navigationTitle("Rate / note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(LR.Color.ink)
                }
            }
        }
    }
}
