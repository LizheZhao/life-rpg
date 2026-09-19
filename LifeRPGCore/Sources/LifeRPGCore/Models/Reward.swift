import Foundation
import SwiftData

@Model public final class Reward {
    public var id: UUID = UUID()
    public var name: String = ""
    public var estimatedCost: Double = 0          // real currency, 0 means a virtual item
    public var virtualKind: String?               // "cancel_hard" / "extend_epic" / "streak_freeze"
    public var fixedCoins: Int?                   // virtual items are priced directly
    public var isActive: Bool = true

    public init() {}
}
