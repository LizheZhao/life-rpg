import Foundation

extension Replan.Change {
    /// The body of the re-plan alert: why it was offered, then what would happen, counts only.
    public var message: String {
        func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
        var lines = toRecovery != fromRecovery
            ? [toRecovery ? "Recovery starts today. Easy quests only."
                          : "Recovery is over. Today follows your readings again."]
            : ["Readings now say \(toTier.rawValue), not \(fromTier.rawValue)."]
        if keptQuests > 0 { lines.append("\(count(keptQuests, "quest")) \(keptQuests == 1 ? "stays" : "stay").") }
        if droppedQuests > 0 {
            lines.append("\(count(droppedQuests, "quest")) would be dropped.")
        }
        if newQuests > 0 { lines.append("\(count(newQuests, "new quest")) would be drawn.") }
        if adjustedRoutines > 0 {
            lines.append("\(count(adjustedRoutines, "routine")) would switch version.")
        }
        if restedRoutines > 0 { lines.append("\(count(restedRoutines, "routine")) set aside.") }
        return lines.joined(separator: "\n")
    }
}
