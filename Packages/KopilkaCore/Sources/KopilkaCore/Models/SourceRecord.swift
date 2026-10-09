import Foundation
import SwiftData

/// Неизменяемый по смыслу след источника: после init поля не трогаем.
@Model
public final class SourceRecord {
    public var kind: SourceKind
    @Attribute(.unique) public var key: String
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
    public var entry: JournalEntry?

    public init(
        kind: SourceKind,
        key: String,
        receivedAt: Date,
        operationDay: CalendarDay? = nil,
        processingDay: CalendarDay? = nil,
        rawDescription: String? = nil,
        operationAmount: Decimal? = nil,
        currency: String? = nil,
        incomeAmount: Decimal? = nil,
        expenseAmount: Decimal? = nil,
        feeAmount: Decimal? = nil,
        cardOrAccount: String? = nil,
        rawText: String? = nil
    ) {
        self.kind = kind
        self.key = key
        self.receivedAt = receivedAt
        self.operationDay = operationDay
        self.processingDay = processingDay
        self.rawDescription = rawDescription
        self.operationAmount = operationAmount
        self.currency = currency
        self.incomeAmount = incomeAmount
        self.expenseAmount = expenseAmount
        self.feeAmount = feeAmount
        self.cardOrAccount = cardOrAccount
        self.rawText = rawText
    }

    /// Источник «выписка» из строки PDF.
    public convenience init(row: StatementRow, key: String, receivedAt: Date) {
        self.init(
            kind: .statement,
            key: key,
            receivedAt: receivedAt,
            operationDay: row.operationDay,
            processingDay: row.processingDay,
            rawDescription: row.description,
            operationAmount: row.operationAmount,
            currency: row.currency,
            incomeAmount: row.incomeAmount,
            expenseAmount: row.expenseAmount,
            feeAmount: row.feeAmount,
            cardOrAccount: row.cardOrAccount
        )
    }
}
