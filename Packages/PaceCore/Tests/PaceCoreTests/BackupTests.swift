import Foundation
import SwiftData
import Testing
@testable import PaceCore

@Suite struct BackupTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeContext() throws -> ModelContext {
        ModelContext(try makeModelContainer(inMemory: true))
    }

    private func fillContext(_ context: ModelContext) throws {
        let card = Account(kind: .card, title: "Карта", number: "KZ1", anchorBalance: Decimal(string: "85430.55")!, anchorDay: CalendarDay(dotted: "01.10.2026"))
        let deposit = Account(kind: .deposit, title: "Депозит", number: "KZ2", anchorBalance: 1_000_000)
        context.insert(card)
        context.insert(deposit)

        let groceries = SpendingCategory(id: "groceries", name: "Продукты", iconName: "cart.fill", kind: .flexible, monthlyLimit: 120_000, expectedMonthlyAmount: 90_000, warnAtPercent: 70, sortOrder: 3)
        let salary = SpendingCategory(id: "salary", name: "Зарплата", iconName: "banknote.fill", kind: .income)
        context.insert(groceries)
        context.insert(salary)

        context.insert(MerchantRule(merchantKey: "MAGNUM", categoryId: "groceries", title: "Магнум", isBuiltIn: false))
        context.insert(MerchantRule(merchantKey: "GLOVO", categoryId: "foodDelivery", isBuiltIn: true))
        context.insert(AmountRule(minAmount: 100, maxAmount: 200, afterEvent: .salary, windowDays: 3, categoryId: "ownTransfer", targetAccountKind: .ownOtherCard, sortOrder: 2))
        context.insert(AppSettings(theme: .glow, periodMode: .halfMonth, employerName: "Работодатель", isApplePayEnabled: true, monthlySavingsGoal: 50_000, hasFinishedSetup: true, appearance: .dark))

        let purchase = JournalEntry(
            day: CalendarDay(dotted: "05.10.2026")!, time: now, type: .expense, amount: Decimal(string: "1500.25")!, feeAmount: 10,
            account: card, counterAccount: deposit, title: "Magnum", merchantKey: "MAGNUM", categoryId: "groceries",
            note: "заметка", isReviewed: true, affectsBalance: false, createdAt: now
        )
        let duplicate = JournalEntry(day: CalendarDay(dotted: "05.10.2026")!, type: .expense, amount: 1500, title: "Magnum", merchantKey: "MAGNUM", createdAt: now)
        let merged = JournalEntry(day: CalendarDay(dotted: "05.10.2026")!, type: .expense, amount: 1500, title: "Magnum", createdAt: now)
        duplicate.possibleDuplicateOf = purchase
        merged.mergedInto = purchase
        context.insert(purchase)
        context.insert(duplicate)
        context.insert(merged)

        let statementSource = SourceRecord(
            kind: .statement, key: "stmt:1", receivedAt: now,
            operationDay: CalendarDay(dotted: "05.10.2026"), processingDay: CalendarDay(dotted: "06.10.2026"),
            rawDescription: "Purchase MAGNUM", operationAmount: Decimal(string: "-1500.25"), currency: "KZT",
            incomeAmount: 0, expenseAmount: Decimal(string: "1500.25"), feeAmount: 10, cardOrAccount: "5522"
        )
        let smsSource = SourceRecord(kind: .sms, key: "sms:1", receivedAt: now, rawText: "Покупка 1 500,25 KZT MAGNUM")
        purchase.sources.append(statementSource)
        purchase.sources.append(smsSource)
        merged.sources.append(SourceRecord(kind: .applePay, key: "ap:1", receivedAt: now))
        try context.save()
    }

    private func makeSnapshot(_ context: ModelContext) throws -> [String] {
        let entries = try context.fetch(FetchDescriptor<JournalEntry>())
        let entryLines = entries.map { entry in
            [
                entry.id.uuidString, "\(entry.day)", "\(String(describing: entry.time))", "\(entry.type)", "\(entry.amount)", "\(entry.feeAmount)",
                entry.account?.number ?? "-", entry.counterAccount?.number ?? "-", entry.title, entry.merchantKey, entry.categoryId ?? "-",
                entry.note, "\(entry.isReviewed)", entry.possibleDuplicateOf?.id.uuidString ?? "-", entry.mergedInto?.id.uuidString ?? "-",
                "\(entry.affectsBalance)", "\(entry.createdAt)",
                entry.sources.map { source in "\(source.kind)|\(source.key)|\(String(describing: source.rawText))|\(String(describing: source.operationAmount))|\(String(describing: source.processingDay))|\(source.receivedAt)" }.sorted().joined(separator: ";"),
            ].joined(separator: "#")
        }
        let accounts = try context.fetch(FetchDescriptor<Account>()).map { account in
            "\(account.kind)|\(account.title)|\(account.number)|\(account.anchorBalance)|\(String(describing: account.anchorDay))"
        }
        let categories = try context.fetch(FetchDescriptor<SpendingCategory>()).map { category in
            "\(category.id)|\(category.name)|\(category.iconName)|\(category.kind)|\(String(describing: category.monthlyLimit))|\(String(describing: category.expectedMonthlyAmount))|\(category.warnAtPercent)|\(category.sortOrder)"
        }
        let merchantRules = try context.fetch(FetchDescriptor<MerchantRule>()).map { rule in
            "\(rule.merchantKey)|\(rule.categoryId)|\(String(describing: rule.title))|\(rule.isBuiltIn)"
        }
        let amountRules = try context.fetch(FetchDescriptor<AmountRule>()).map { rule in
            "\(rule.minAmount)|\(rule.maxAmount)|\(String(describing: rule.afterEvent))|\(rule.windowDays)|\(String(describing: rule.categoryId))|\(String(describing: rule.targetAccountKind))|\(rule.sortOrder)"
        }
        let settings = try context.fetch(FetchDescriptor<AppSettings>()).map { item in
            "\(item.theme)|\(item.periodMode)|\(item.employerName)|\(item.isApplePayEnabled)|\(item.isSmsEnabled)|\(item.shouldShowRemainingAfterPayment)|\(item.monthlySavingsGoal)|\(item.hasFinishedSetup)|\(item.appearance)"
        }
        return (entryLines + accounts + categories + merchantRules + amountRules + settings).sorted()
    }

    @Test func roundTripIntoEmptyContainerKeepsEverything() throws {
        let source = try makeContext()
        try fillContext(source)
        let backup = try makeBackup(context: source)

        let target = try makeContext()
        try restoreBackup(backup, context: target)

        #expect(try makeSnapshot(target) == makeSnapshot(source))
        #expect(try target.fetch(FetchDescriptor<SourceRecord>()).count == 3)
    }

    @Test func restoreReplacesExistingData() throws {
        let source = try makeContext()
        try fillContext(source)
        let backup = try makeBackup(context: source)

        let target = try makeContext()
        target.insert(JournalEntry(day: CalendarDay(dotted: "01.01.2026")!, type: .income, amount: 5, title: "Старая"))
        target.insert(SourceRecord(kind: .manual, key: "sms:1", receivedAt: now))
        target.insert(MerchantRule(merchantKey: "MAGNUM", categoryId: "cafes"))
        try target.save()
        try restoreBackup(backup, context: target)

        #expect(try makeSnapshot(target) == makeSnapshot(source))
    }

    @Test func brokenFileThrowsAndKeepsExistingData() throws {
        let target = try makeContext()
        target.insert(JournalEntry(day: CalendarDay(dotted: "01.01.2026")!, type: .income, amount: 5, title: "Старая"))
        try target.save()

        #expect(throws: Error.self) { try restoreBackup(Data("не json".utf8), context: target) }
        #expect(try target.fetch(FetchDescriptor<JournalEntry>()).count == 1)
    }

    @Test func danglingReferenceThrowsAndKeepsExistingData() throws {
        let source = try makeContext()
        try fillContext(source)
        var file = try JSONDecoder().decode(BackupFile.self, from: makeBackup(context: source))
        file.entries[0].mergedIntoId = UUID()
        let broken = try JSONEncoder().encode(file)

        let target = try makeContext()
        target.insert(JournalEntry(day: CalendarDay(dotted: "01.01.2026")!, type: .income, amount: 5, title: "Старая"))
        try target.save()

        #expect(throws: BackupError.self) { try restoreBackup(broken, context: target) }
        #expect(try target.fetch(FetchDescriptor<JournalEntry>()).count == 1)
    }

    private struct InjectedFailure: Error {}

    @Test func failureAfterDeletionRollsBackToOriginalData() throws {
        let container = try makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        try fillContext(context)
        let before = try makeSnapshot(context)
        let backup = try makeBackup(context: ModelContext(try makeModelContainer(inMemory: true)))

        #expect(throws: InjectedFailure.self) {
            try restoreBackup(backup, context: context, afterDelete: { throw InjectedFailure() })
        }

        #expect(try makeSnapshot(context) == before)
        #expect(try makeSnapshot(ModelContext(container)) == before)
    }

    @Test func eraseAllDataLeavesEmptyDatabase() throws {
        let context = try makeContext()
        try fillContext(context)

        try eraseAllData(context: context)

        #expect(try makeSnapshot(context).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<JournalEntry>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SourceRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<AppSettings>()) == 0)
    }
}
