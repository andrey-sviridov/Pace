import Foundation

// Плоские копии моделей для JSON: SwiftData-объекты внутрь не попадают.
// Связи записаны ссылками: записи — по UUID, счета — по номеру в массиве `accounts` (у счёта нет своего id).

public struct BackupFile: Codable {
    public static let currentVersion = 1

    public var version: Int
    public var accounts: [AccountBackup]
    public var categories: [CategoryBackup]
    public var merchantRules: [MerchantRuleBackup]
    public var amountRules: [AmountRuleBackup]
    public var settings: [SettingsBackup]
    public var entries: [EntryBackup]
    public var sources: [SourceBackup]
}

public struct AccountBackup: Codable {
    public var kind: AccountKind
    public var title: String
    public var number: String
    public var anchorBalance: Decimal
    public var anchorDay: CalendarDay?
}

public struct CategoryBackup: Codable {
    public var id: String
    public var name: String
    public var iconName: String
    public var kind: CategoryKind
    public var monthlyLimit: Decimal?
    public var expectedMonthlyAmount: Decimal?
    public var warnAtPercent: Int
    public var sortOrder: Int
}

public struct MerchantRuleBackup: Codable {
    public var merchantKey: String
    public var categoryId: String
    public var title: String?
    public var isBuiltIn: Bool
}

public struct AmountRuleBackup: Codable {
    public var minAmount: Decimal
    public var maxAmount: Decimal
    public var afterEvent: SalaryEventKind?
    public var windowDays: Int
    public var categoryId: String?
    public var targetAccountKind: AccountKind?
    public var sortOrder: Int
}

public struct SettingsBackup: Codable {
    public var theme: ThemeName
    public var periodMode: PeriodMode
    public var employerName: String
    public var isApplePayEnabled: Bool
    public var isSmsEnabled: Bool
    public var shouldShowRemainingAfterPayment: Bool
    public var monthlySavingsGoal: Decimal
    public var hasFinishedSetup: Bool
    // Необязательные: в копиях, сделанных до появления этих настроек, их нет.
    public var hasAdvance: Bool?
    public var shouldShowOperationTime: Bool?
    public var appearance: AppearanceMode?
}

public struct EntryBackup: Codable {
    public var id: UUID
    public var day: CalendarDay
    public var time: Date?
    public var type: EntryType
    public var amount: Decimal
    public var feeAmount: Decimal
    public var accountIndex: Int?
    public var counterAccountIndex: Int?
    public var title: String
    public var merchantKey: String
    public var categoryId: String?
    public var note: String
    public var isReviewed: Bool
    public var possibleDuplicateOfId: UUID?
    public var mergedIntoId: UUID?
    public var affectsBalance: Bool
    public var createdAt: Date
}

public struct SourceBackup: Codable {
    public var kind: SourceKind
    public var key: String
    public var operationDay: CalendarDay?
    public var processingDay: CalendarDay?
    public var rawDescription: String?
    public var operationAmount: Decimal?
    public var currency: String?
    public var incomeAmount: Decimal?
    public var expenseAmount: Decimal?
    public var feeAmount: Decimal?
    public var cardOrAccount: String?
    public var rawText: String?
    public var receivedAt: Date
    public var entryId: UUID?
}
