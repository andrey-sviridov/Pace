import Foundation
import SwiftData

@Model
public final class JournalEntry {
    public var id: UUID
    public var day: CalendarDay
    /// Время есть только у Apple Pay и SMS.
    public var time: Date?
    public var type: EntryType
    /// Всегда больше нуля; направление задаёт `type`.
    public var amount: Decimal
    public var feeAmount: Decimal
    public var account: Account?
    public var counterAccount: Account?
    public var title: String
    public var merchantKey: String
    public var categoryId: String?
    public var note: String
    public var isReviewed: Bool
    @Relationship(deleteRule: .nullify) public var possibleDuplicateOf: JournalEntry?
    @Relationship(deleteRule: .nullify) public var mergedInto: JournalEntry?
    public var affectsBalance: Bool
    public var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \SourceRecord.entry)
    public var sources: [SourceRecord] = []

    public init(
        id: UUID = UUID(),
        day: CalendarDay,
        time: Date? = nil,
        type: EntryType,
        amount: Decimal,
        feeAmount: Decimal = 0,
        account: Account? = nil,
        counterAccount: Account? = nil,
        title: String,
        merchantKey: String = "",
        categoryId: String? = nil,
        note: String = "",
        isReviewed: Bool = false,
        affectsBalance: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.day = day
        self.time = time
        self.type = type
        self.amount = amount
        self.feeAmount = feeAmount
        self.account = account
        self.counterAccount = counterAccount
        self.title = title
        self.merchantKey = merchantKey
        self.categoryId = categoryId
        self.note = note
        self.isReviewed = isReviewed
        self.affectsBalance = affectsBalance
        self.createdAt = createdAt
    }
}
