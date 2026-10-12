import LifeRPGCore
import SwiftData
import SwiftUI

/// What the starter library has that this library doesn't: a list to tick, `Add` for the ticked
/// ones, and `Hide these` to stop being offered exactly what is listed now. Nothing is added by
/// itself, and a row the user renamed or deleted is never listed (`StarterUpdate`).
struct StarterUpdateSheet: View {
    let items: [StarterUpdate.Item]
    /// Adds the ticked rows; throws what Core throws.
    let onAdd: (Set<String>) throws -> Void
    /// Records these ids as not wanted.
    let onHide: (Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String>
    @State private var error: String?

    init(items: [StarterUpdate.Item], onAdd: @escaping (Set<String>) throws -> Void, onHide: @escaping (Set<String>) -> Void) {
        self.items = items; self.onAdd = onAdd; self.onHide = onHide
        _picked = State(initialValue: Set(items.map(\.id)))
    }

    private var quests: [StarterUpdate.Item] {
        items.filter { $0.kind == .quest }.sorted {
            (Difficulty.allCases.firstIndex(of: $0.difficulty) ?? 0, $0.text) < (Difficulty.allCases.firstIndex(of: $1.difficulty) ?? 0, $1.text)
        }
    }

    private var routines: [StarterUpdate.Item] {
        items.filter { $0.kind == .routine }.sorted { ($0.isLightVersion ? 1 : 0, $0.text) < ($1.isLightVersion ? 1 : 0, $1.text) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LR.Spacing.sectionGap) {
                    Text("Pick what you want.")
                        .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !quests.isEmpty { group("Quests", quests) }
                    if !routines.isEmpty { group("Routines", routines) }
                    Button("Hide these") { onHide(Set(items.map(\.id))); dismiss() }
                        .buttonStyle(PillButtonStyle())
                        .accessibilityHint("Stops offering exactly the rows listed here")
                    if let error { BannerView(message: error) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .safeAreaInset(edge: .bottom) {
                ConfirmBar(title: picked.isEmpty ? "Add" : "Add \(picked.count)", enabled: !picked.isEmpty) { add() }
            }
            .background(LR.Color.canvas.ignoresSafeArea())
            .navigationTitle("New in the starter library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(LR.Color.ink)
                }
            }
        }
    }

    private func group(_ title: String, _ rows: [StarterUpdate.Item]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: title)
            ForEach(rows) { row($0) }
        }
    }

    private func row(_ item: StarterUpdate.Item) -> some View {
        let on = picked.contains(item.id)
        return Button {
            if on { picked.remove(item.id) } else { picked.insert(item.id) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(on ? LR.Color.accent : LR.Color.iconNeutral)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.text).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    FlowRow(spacing: 6) {
                        PillLabel(text: item.difficulty.rawValue.capitalized, style: .tint(QuestTint(item.difficulty)), dense: true)
                        if item.isLightVersion { PillLabel(text: "lighter version", dense: true) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lrCard(.surface, radius: LR.Radius.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.text)
        .accessibilityValue([item.difficulty.rawValue, item.isLightVersion ? "lighter version" : nil, on ? "selected" : "not selected"]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }

    private func add() {
        do {
            try onAdd(picked)
            dismiss()
        } catch {
            self.error = "\(error)"
        }
    }
}
