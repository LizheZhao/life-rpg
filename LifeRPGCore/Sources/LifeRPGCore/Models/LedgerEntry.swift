import Foundation
import SwiftData

/// Balance is always derived by summing entries; never cache it.
@Model public final class LedgerEntry {
    public var id: UUID = UUID()
    public var timestamp: Date = Date()
    public var dayKey: String = ""
    public var kind: String = "quest"             // quest / routine / redeem / reroll / penalty / skip / adjust
    public var points: Int = 0                    // spending and penalties are negative
    public var refID: UUID?
    public var note: String = ""

    public init() {}
}
