import Foundation
import SwiftData

public enum SalaryEventKind: String, Codable, Sendable {
    case advance, salary
}

/// Правило «сумма в диапазоне после аванса/зарплаты → категория или счёт».
@Model
public final class AmountRule {
    public var minAmount: Decimal
    public var maxAmount: Decimal
    public var afterEvent: SalaryEventKind?
    public var windowDays: Int
    public var categoryId: String?
    public var targetAccountKind: AccountKind?
    public var sortOrder: Int

    public init(
        minAmount: Decimal,
        maxAmount: Decimal,
        afterEvent: SalaryEventKind? = nil,
        windowDays: Int = 0,
        categoryId: String? = nil,
        targetAccountKind: AccountKind? = nil,
        sortOrder: Int = 0
    ) {
        self.minAmount = minAmount
        self.maxAmount = maxAmount
        self.afterEvent = afterEvent
        self.windowDays = windowDays
        self.categoryId = categoryId
        self.targetAccountKind = targetAccountKind
        self.sortOrder = sortOrder
    }
}
