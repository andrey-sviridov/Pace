import Foundation
import SwiftData

@Model
public final class Account {
    public var kind: AccountKind
    public var title: String
    public var number: String
    /// Остаток в точке отсчёта (§5.9).
    public var anchorBalance: Decimal
    public var anchorDay: CalendarDay?

    public init(kind: AccountKind, title: String, number: String, anchorBalance: Decimal = 0, anchorDay: CalendarDay? = nil) {
        self.kind = kind
        self.title = title
        self.number = number
        self.anchorBalance = anchorBalance
        self.anchorDay = anchorDay
    }
}
