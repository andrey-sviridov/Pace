import Foundation
import SwiftData

@Model
public final class SpendingCategory {
    /// Английский slug, например "groceries".
    @Attribute(.unique) public var id: String
    public var name: String
    public var iconName: String
    public var kind: CategoryKind
    public var monthlyLimit: Decimal?
    public var expectedMonthlyAmount: Decimal?
    public var warnAtPercent: Int
    public var sortOrder: Int

    public init(
        id: String,
        name: String,
        iconName: String,
        kind: CategoryKind,
        monthlyLimit: Decimal? = nil,
        expectedMonthlyAmount: Decimal? = nil,
        warnAtPercent: Int = 85,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.kind = kind
        self.monthlyLimit = monthlyLimit
        self.expectedMonthlyAmount = expectedMonthlyAmount
        self.warnAtPercent = warnAtPercent
        self.sortOrder = sortOrder
    }
}
