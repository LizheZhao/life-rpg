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

/// Everything done today, as the stack of cards it was while open. Done rows complete nothing and
/// their `⋯` holds only what still applies to something done (`actions`: Rate / note); only the
/// epic still expands on a tap.
struct CompletedStackView: View {
    let state: CompletedStackState
    @Binding var expanded: Bool
    var actions: (CompletedItem) -> [CardAction] = { _ in [] }

    var body: some View {
        StackedCards(title: "Completed", summary: state.summary,
                     accessibilityLabel: state.accessibilityLabel,
                     items: state.items, expanded: $expanded, fill: \.fill) { item in
            switch item {
            case .quest(let state): QuestRowView(state: state, actions: actions(item), onComplete: {})
            case .routine(let state): RoutineRowView(state: state, actions: actions(item), onComplete: {})
            case .epic(let state): EpicCardView(state: state, actions: actions(item), onComplete: {})
            }
        }
    }
}
