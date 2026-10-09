import Foundation
import SwiftData
import Testing
@testable import KopilkaCore

@Suite struct RealtimeOperationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day = CalendarDay(dotted: "15.01.2027")!

    private func makeContext() throws -> ModelContext {
        ModelContext(try makeModelContainer(inMemory: true))
    }

    private func record(
        _ context: ModelContext,
        card: Account,
        type: EntryType = .expense,
        amount: Decimal = 1500,
        merchant: String = "MAGNUM.ASF36.",
        kind: SourceKind = .applePay,
        at time: Date? = nil,
        salaryHistory: [Decimal] = []
    ) throws -> JournalEntry {
        try recordRealtimeOperation(
            kind: kind,
            day: day,
            time: time ?? now,
            type: type,
            amount: amount,
            rawMerchant: merchant,
            rawText: nil,
            account: card,
            rules: makeBuiltInMerchantRules(),
            salaryHistory: salaryHistory,
            context: context,
            now: now
        )
    }

    private func makeCard(_ context: ModelContext) -> Account {
        let card = Account(kind: .card, title: "Карта", number: "KZ1")
        context.insert(card)
        return card
    }

    @Test func createsNewEntryWhenNothingMatches() throws {
        let context = try makeContext()
        let card = makeCard(context)

        let entry = try record(context, card: card)

        #expect(entry.merchantKey == makeMerchantKey("MAGNUM.ASF36."))
        #expect(entry.title == "Magnum")
        #expect(entry.categoryId == "groceries")
        #expect(entry.account === card)
        #expect(entry.isReviewed == false)
        #expect(entry.affectsBalance == true)
        #expect(entry.time == now)
        #expect(entry.day == day)
        #expect(entry.sources.count == 1)
        #expect(entry.sources.first?.key == "applePay:\(ISO8601DateFormatter().string(from: now)):1500:MAGNUM")
    }

    @Test func attachesSmsToApplePayEntry() throws {
        let context = try makeContext()
        let card = makeCard(context)
        let first = try record(context, card: card)

        let second = try record(context, card: card, merchant: "Magnum", kind: .sms, at: now.addingTimeInterval(120))

        #expect(second === first)
        #expect(first.sources.map { source in source.kind }.sorted { a, b in a.rawValue < b.rawValue } == [.applePay, .sms])
        #expect(try context.fetch(FetchDescriptor<JournalEntry>()).count == 1)
    }

    @Test func repeatedSameOperationDoesNotDuplicateSource() throws {
        let context = try makeContext()
        let card = makeCard(context)
        let first = try record(context, card: card)

        let again = try record(context, card: card)

        #expect(again === first)
        #expect(try context.fetch(FetchDescriptor<SourceRecord>()).count == 1)
    }

    @Test func marksPossibleDuplicateWhenMerchantDiffers() throws {
        let context = try makeContext()
        let card = makeCard(context)
        let first = try record(context, card: card, merchant: "MAGNUM")

        let second = try record(context, card: card, merchant: "GLOVO", kind: .sms, at: now.addingTimeInterval(60))

        #expect(second !== first)
        #expect(second.possibleDuplicateOf === first)
    }

    @Test func largeIncomeMatchingSalaryHistoryBecomesSalary() throws {
        let context = try makeContext()
        let card = makeCard(context)

        let entry = try record(context, card: card, type: .income, amount: 400_000, merchant: "", salaryHistory: [405_000, 395_000, 410_000])

        #expect(entry.categoryId == "salary")
    }

    @Test func smallIncomeIsNotSalary() throws {
        let context = try makeContext()
        let card = makeCard(context)

        let entry = try record(context, card: card, type: .income, amount: 10_000, merchant: "", salaryHistory: [400_000])
        let withoutHistory = try record(context, card: card, type: .income, amount: 400_000, merchant: "", kind: .sms, at: now.addingTimeInterval(3600), salaryHistory: [])

        #expect(entry.categoryId != "salary")
        #expect(withoutHistory.categoryId != "salary")
    }
}
