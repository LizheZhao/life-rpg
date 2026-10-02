import SwiftUI

/// Progress to the next level as a 10 x 2 grid of dots. New dots light one after another, 40 ms
/// apart; the count itself comes from `Economy.levelDots`, never from this view.
struct LevelDotGrid: View {
    let filled: Int
    let total: Int
    /// 20 for one row of small dots; 10 for the two-row grid the accessibility sizes use.
    var columns = 10
    var spacing: CGFloat = 8

    @State private var shown: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(filled: Int, total: Int = 20, columns: Int = 10, spacing: CGFloat = 8) {
        self.filled = filled
        self.total = total
        self.columns = columns
        self.spacing = spacing
        _shown = State(initialValue: min(max(filled, 0), total))
    }

    var body: some View {
        let grid = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns)
        LazyVGrid(columns: grid, spacing: spacing) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(LR.Color.dotEmpty)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        // The fill grows from nothing, so the spring's overshoot reads as a pop.
                        Circle().fill(LR.Color.dotFill)
                            .scaleEffect(index < shown ? 1 : 0.001)
                            .opacity(index < shown ? 1 : 0)
                    }
            }
        }
        .accessibilityHidden(true)
        .task(id: filled) { await advance() }
    }

    private func advance() async {
        let target = min(max(filled, 0), total)
        if reduceMotion || target <= shown {
            withAnimation(.easeInOut(duration: 0.2)) { shown = target }
            return
        }
        for next in (shown + 1)...target {
            try? await Task.sleep(for: .milliseconds(40))
            if Task.isCancelled { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { shown = next }
        }
    }
}
