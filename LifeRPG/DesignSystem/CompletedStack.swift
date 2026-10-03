import LifeRPGCore
import SwiftUI

extension CompletedItem {
    /// The colour of the card the item had while open: a quest keeps its tint when done.
    var fill: Color {
        switch self {
        case .quest(let s): s.tint.color
        case .routine: QuestTint.routine.color
        case .epic: QuestTint.epic.color
        }
    }
}

/// Everything done today, as the stack of cards it was while open. Done rows carry no menu and
/// complete nothing; only the epic still expands on a tap.
struct CompletedStackView: View {
    let state: CompletedStackState
    @Binding var expanded: Bool

    var body: some View {
        StackedCards(title: "Completed", summary: state.summary,
                     accessibilityLabel: state.accessibilityLabel,
                     items: state.items, expanded: $expanded, fill: \.fill) { item in
            switch item {
            case .quest(let state): QuestRowView(state: state, onComplete: {})
            case .routine(let state): RoutineRowView(state: state, onComplete: {})
            case .epic(let state): EpicCardView(state: state, onComplete: {})
            }
        }
    }
}
