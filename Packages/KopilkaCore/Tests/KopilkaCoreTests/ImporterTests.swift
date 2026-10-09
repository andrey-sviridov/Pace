import Foundation
import SwiftData
import Testing
@testable import KopilkaCore

@Suite struct ImporterTests {
    private let importedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeRow(
        _ dotted: String,
        _ description: String,
        operationAmount: Decimal,
        income: Decimal = 0,
        expense: Decimal = 0,
        fee: Decimal = 0,
        card: String = "552204******2936"
    ) -> StatementRow {
        let day = CalendarDay(dotted: dotted)!
        return StatementRow(
            operationDay: day,
            processingDay: day,
            description: description,
            operationAmount: operationAmount,
            currency: "KZT",
            incomeAmount: income,
            expenseAmount: expense,
            feeAmount: fee,
            cardOrAccount: card
        )
    }

    // Итоги считаем из строк, чтобы checkTotals проходил; для проверки расхождения их подменяют.
    private func makeStatement(rows: [StatementRow], accountNumber: String = "KZ126010002008249310", accountType: String = "Текущий счет", totals: StatementTotals? = nil) -> ParsedStatement {
        let rowTotals = StatementTotals(
            income: rows.reduce(Decimal(0)) { sum, row in sum + row.incomeAmount },
            expense: rows.reduce(Decimal(0)) { sum, row in sum + row.expenseAmount },
            fee: rows.reduce(Decimal(0)) { sum, row in sum + row.feeAmount }
        )
        let header = StatementHeader(
            accountNumber: accountNumber,
            accountType: accountType,
            periodStart: CalendarDay(dotted: "01.07.2026")!,
            periodEnd: CalendarDay(dotted: "31.07.2026")!,
            generatedOn: CalendarDay(dotted: "31.07.2026")!,
            openingBalance: 0,
            closingBalance: 0,
            availableAmount: nil,
            totals: totals ?? rowTotals
        )
        return ParsedStatement(header: header, rows: rows)
    }

    /// Шесть строк из брифа: Magnum, аванс, на депозит, с депозита, 54 000 после аванса, неизвестный ИП.
    private func makeSixRowStatement() -> ParsedStatement {
        makeStatement(rows: [
            makeRow("10.07.2026", "Операция оплаты у коммерсанта MAGNUM.ASF36.", operationAmount: -1398, expense: -1398),
            makeRow("15.07.2026", "Поступление на счет ТОО \"АЦЭПАК\"", operationAmount: 400_000, income: 400_000),
            makeRow("15.07.2026", "Перевод на депозит", operationAmount: -100_000, expense: -100_000),
            makeRow("16.07.2026", "Зачисление с депозита", operationAmount: 10_000, income: 10_000),
            makeRow("17.07.2026", "Перевод на другую карту", operationAmount: -54_000, expense: -54_200),
            makeRow("20.07.2026", "Операция оплаты у коммерсанта IP KUZNETSOV", operationAmount: -2500, expense: -2500),
        ])
    }

    private func makeContext() throws -> ModelContext {
        ModelContext(try makeModelContainer(inMemory: true))
    }

    private func findEntry(titled title: String, in context: ModelContext) throws -> JournalEntry {
        let entries = try context.fetch(FetchDescriptor<JournalEntry>())
        return try #require(entries.first { entry in entry.title == title })
    }

    @Test func firstImportAddsAllRowsAndClassifiesThem() throws {
        let context = try makeContext()

        let result = try importStatement(makeSixRowStatement(), mode: .initialHistory, context: context, now: importedAt)

        #expect(result.addedCount == 6)
        #expect(result.alreadyKnownCount == 0)
        #expect(result.accountKind == .card)
        #expect(try findEntry(titled: "На депозит", in: context).type == .transfer)
        #expect(try findEntry(titled: "С депозита", in: context).type == .transfer)
        #expect(try findEntry(titled: "Ip Kuznetsov", in: context).isReviewed == false)
        #expect(try findEntry(titled: "Magnum", in: context).categoryId == "groceries")
        #expect(try findEntry(titled: "Зарплата", in: context).categoryId == "salary")
        #expect(try findEntry(titled: "Перевод на другую карту", in: context).categoryId == "installments")
        #expect(result.needsReviewCount == 1)
        #expect(try context.fetch(FetchDescriptor<SourceRecord>()).count == 6)
    }

    @Test func secondImportOfSameStatementAddsNothing() throws {
        let context = try makeContext()
        _ = try importStatement(makeSixRowStatement(), mode: .initialHistory, context: context, now: importedAt)

        let result = try importStatement(makeSixRowStatement(), mode: .initialHistory, context: context, now: importedAt)

        #expect(result.addedCount == 0)
        #expect(result.alreadyKnownCount == 6)
        #expect(try context.fetch(FetchDescriptor<JournalEntry>()).count == 6)
    }

    @Test func initialHistoryNeverAffectsBalance() throws {
        let context = try makeContext()

        _ = try importStatement(makeSixRowStatement(), mode: .initialHistory, context: context, now: importedAt)

        let entries = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(entries.allSatisfy { entry in !entry.affectsBalance })
    }

    @Test func regularImportAffectsBalanceFromAnchorDay() throws {
        let context = try makeContext()
        context.insert(Account(kind: .card, title: "Карта *9310", number: "KZ126010002008249310", anchorDay: CalendarDay(dotted: "16.07.2026")!))
        try context.save()

        _ = try importStatement(makeSixRowStatement(), mode: .regular, context: context, now: importedAt)

        let entries = try context.fetch(FetchDescriptor<JournalEntry>())
        let anchorDay = CalendarDay(dotted: "16.07.2026")!
        #expect(entries.count == 6)
        #expect(entries.filter { entry in entry.day >= anchorDay }.allSatisfy { entry in entry.affectsBalance })
        #expect(entries.filter { entry in entry.day < anchorDay }.allSatisfy { entry in !entry.affectsBalance })
    }

    @Test func unknownAccountThrowsAndWritesNothing() throws {
        let context = try makeContext()

        #expect(throws: ImportError.unknownAccount(number: "KZ126010002008249310")) {
            try importStatement(makeSixRowStatement(), mode: .regular, context: context, now: importedAt)
        }

        #expect(try context.fetch(FetchDescriptor<JournalEntry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SourceRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Account>()).isEmpty)
    }

    @Test func totalsMismatchThrowsAndWritesNothing() throws {
        let context = try makeContext()
        let wrongTotals = StatementTotals(income: 1, expense: 0, fee: 0)
        let statement = makeStatement(rows: makeSixRowStatement().rows, totals: wrongTotals)

        #expect(throws: StatementError.self) {
            try importStatement(statement, mode: .initialHistory, context: context, now: importedAt)
        }

        #expect(try context.fetch(FetchDescriptor<JournalEntry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Account>()).isEmpty)
    }

    @Test func initialHistoryCreatesCardAccountNamedByMostFrequentCard() throws {
        let context = try makeContext()
        let statement = makeStatement(rows: [
            makeRow("10.07.2026", "Операция оплаты у коммерсанта MAGNUM", operationAmount: -100, expense: -100),
            makeRow("11.07.2026", "Операция оплаты у коммерсанта MAGNUM", operationAmount: -200, expense: -200),
            makeRow("12.07.2026", "Операция оплаты у коммерсанта MAGNUM", operationAmount: -300, expense: -300, card: "440563******7777"),
            makeRow("13.07.2026", "Ежемесячная комиссия RegularCharge", operationAmount: 0, fee: -150, card: "KZ126010002008249310"),
        ])

        _ = try importStatement(statement, mode: .initialHistory, context: context, now: importedAt)

        let accounts = try context.fetch(FetchDescriptor<Account>())
        #expect(accounts.count == 1)
        #expect(accounts.first?.kind == .card)
        #expect(accounts.first?.title == "Карта *2936")
        #expect(accounts.first?.anchorDay == nil)
        let entries = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(entries.allSatisfy { entry in entry.account?.number == "KZ126010002008249310" })
    }

    @Test func cardTitleFallsBackToAccountNumberWithoutMaskedCard() throws {
        let context = try makeContext()
        let statement = makeStatement(rows: [
            makeRow("10.07.2026", "Операция оплаты у коммерсанта MAGNUM", operationAmount: -100, expense: -100, card: "KZ126010002008249310"),
        ])

        _ = try importStatement(statement, mode: .initialHistory, context: context, now: importedAt)

        #expect(try context.fetch(FetchDescriptor<Account>()).first?.title == "Карта *9310")
    }

    @Test func depositMovesGoFromSourceToRecipientAccount() throws {
        let context = try makeContext()

        _ = try importStatement(makeSixRowStatement(), mode: .initialHistory, context: context, now: importedAt)

        let toDeposit = try findEntry(titled: "На депозит", in: context)
        let fromDeposit = try findEntry(titled: "С депозита", in: context)
        #expect(toDeposit.account?.kind == .card)
        #expect(toDeposit.counterAccount?.kind == .deposit)
        #expect(fromDeposit.account?.kind == .deposit)
        #expect(fromDeposit.counterAccount?.kind == .card)
        let deposit = try #require(toDeposit.counterAccount)
        #expect(deposit.title == "Депозит" && deposit.number == "" && deposit.anchorBalance == 0 && deposit.anchorDay == nil)
    }

    @Test func secondImportReusesDepositAccount() throws {
        let context = try makeContext()
        _ = try importStatement(makeSixRowStatement(), mode: .initialHistory, context: context, now: importedAt)
        let laterStatement = makeStatement(rows: [
            makeRow("25.07.2026", "Перевод на депозит", operationAmount: -5000, expense: -5000),
        ])

        _ = try importStatement(laterStatement, mode: .initialHistory, context: context, now: importedAt)

        let accounts = try context.fetch(FetchDescriptor<Account>())
        #expect(accounts.filter { account in account.kind == .deposit }.count == 1)
        #expect(accounts.count == 2)
    }

    @Test func depositStatementAdoptsDepositCreatedByCardImport() throws {
        let context = try makeContext()
        _ = try importStatement(makeSixRowStatement(), mode: .initialHistory, context: context, now: importedAt)
        let depositStatement = makeStatement(
            rows: [makeRow("15.07.2026", "Пополнение депозита", operationAmount: 100_000, income: 100_000, card: "KZ999")],
            accountNumber: "KZ999",
            accountType: "Сберегательный депозит"
        )

        let result = try importStatement(depositStatement, mode: .regular, context: context, now: importedAt)

        let deposits = try context.fetch(FetchDescriptor<Account>()).filter { account in account.kind == .deposit }
        #expect(result.accountKind == .deposit)
        #expect(result.addedCount == 1)
        #expect(deposits.count == 1)
        #expect(deposits.first?.number == "KZ999")
        #expect(deposits.first?.title == "Депозит")
        #expect(try findEntry(titled: "На депозит", in: context).counterAccount?.number == "KZ999")
    }

    @Test func purchaseRowWithIncomeIsRefund() throws {
        let context = try makeContext()
        let statement = makeStatement(rows: [
            makeRow("12.07.2026", "Операция оплаты у коммерсанта WILDBERRIES", operationAmount: 11, income: 11),
            makeRow("13.07.2026", "Операция оплаты у коммерсанта IP KUZNETSOV", operationAmount: 50, income: 50),
        ])

        _ = try importStatement(statement, mode: .initialHistory, context: context, now: importedAt)

        let marketplaceRefund = try findEntry(titled: "Wildberries", in: context)
        #expect(marketplaceRefund.type == .income)
        #expect(marketplaceRefund.amount == 11)
        #expect(marketplaceRefund.categoryId == "marketplaces")
        let unknownRefund = try findEntry(titled: "Ip Kuznetsov", in: context)
        #expect(unknownRefund.type == .income)
        #expect(unknownRefund.categoryId == "refunds")
    }

    @Test func transferFeeIsSplitFromAmount() throws {
        let context = try makeContext()
        let statement = makeStatement(rows: [
            makeRow("20.09.2026", "Перевод на другую карту", operationAmount: -30_000, expense: -30_250),
        ])

        _ = try importStatement(statement, mode: .initialHistory, context: context, now: importedAt)

        let entry = try findEntry(titled: "Перевод на другую карту", in: context)
        #expect(entry.type == .expense)
        #expect(entry.amount == 30_000)
        #expect(entry.feeAmount == 250)
        #expect(entry.categoryId == "transfersToPeople")
        #expect(entry.isReviewed == false)
    }

    @Test func transferBeforeKaspiDateBecomesOwnTransfer() throws {
        let context = try makeContext()
        let statement = makeStatement(rows: [
            makeRow("20.01.2026", "Перевод на другую карту", operationAmount: -30_000, expense: -30_200),
        ])

        _ = try importStatement(statement, mode: .initialHistory, context: context, now: importedAt)

        let entry = try findEntry(titled: "На свою карту Kaspi", in: context)
        #expect(entry.type == .transfer)
        #expect(entry.account?.kind == .card)
        #expect(entry.counterAccount?.kind == .ownOtherCard)
        #expect(entry.counterAccount?.title == "Kaspi *3436")
        #expect(entry.categoryId == "ownTransfer")
        #expect(entry.isReviewed)
    }

    @Test func userEditsDoNotBreakReimport() throws {
        let context = try makeContext()
        _ = try importStatement(makeSixRowStatement(), mode: .initialHistory, context: context, now: importedAt)
        let entry = try findEntry(titled: "Ip Kuznetsov", in: context)
        entry.title = "Сапожник"
        entry.categoryId = "home"
        try context.save()

        let result = try importStatement(makeSixRowStatement(), mode: .initialHistory, context: context, now: importedAt)

        #expect(result.addedCount == 0)
        #expect(result.alreadyKnownCount == 6)
    }

    // MARK: - Склейка с Apple Pay

    private func addApplePayEntry(account: Account, context: ModelContext) -> JournalEntry {
        let entry = JournalEntry(
            day: CalendarDay(dotted: "11.08.2026")!,
            time: Date(timeIntervalSince1970: 1_800_000_000),
            type: .expense,
            amount: 1500,
            account: account,
            title: "Magnum",
            merchantKey: "MAGNUM",
            categoryId: "groceries",
            isReviewed: true,
            createdAt: importedAt
        )
        context.insert(entry)
        entry.sources = [SourceRecord(kind: .applePay, key: "applepay-1", receivedAt: importedAt)]
        return entry
    }

    @Test func statementRowAttachesToEarlierApplePayEntry() throws {
        let context = try makeContext()
        let setup = makeStatement(rows: [makeRow("01.08.2026", "Операция оплаты у коммерсанта ARBUZ", operationAmount: -700, expense: -700)])
        _ = try importStatement(setup, mode: .initialHistory, context: context, now: importedAt)
        let account = try #require(try context.fetch(FetchDescriptor<Account>()).first)
        let applePay = addApplePayEntry(account: account, context: context)
        let statement = makeStatement(rows: [makeRow("12.08.2026", "Операция оплаты у коммерсанта MAGNUM.ASF36.", operationAmount: -1500, expense: -1500)])

        let result = try importStatement(statement, mode: .regular, context: context, now: importedAt)

        #expect(result.addedCount == 0)
        #expect(result.attachedCount == 1)
        #expect(applePay.sources.map { source in source.kind }.sorted { first, second in first.rawValue < second.rawValue } == [.applePay, .statement])
        #expect(try context.fetch(FetchDescriptor<JournalEntry>()).count == 2)
    }

    @Test func reimportingAttachedStatementChangesNothing() throws {
        let context = try makeContext()
        let setup = makeStatement(rows: [makeRow("01.08.2026", "Операция оплаты у коммерсанта ARBUZ", operationAmount: -700, expense: -700)])
        _ = try importStatement(setup, mode: .initialHistory, context: context, now: importedAt)
        let account = try #require(try context.fetch(FetchDescriptor<Account>()).first)
        _ = addApplePayEntry(account: account, context: context)
        let statement = makeStatement(rows: [makeRow("12.08.2026", "Операция оплаты у коммерсанта MAGNUM.ASF36.", operationAmount: -1500, expense: -1500)])
        _ = try importStatement(statement, mode: .regular, context: context, now: importedAt)

        let result = try importStatement(statement, mode: .regular, context: context, now: importedAt)

        #expect(result.addedCount == 0)
        #expect(result.attachedCount == 0)
        #expect(result.alreadyKnownCount == 1)
        #expect(try context.fetch(FetchDescriptor<JournalEntry>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<SourceRecord>()).count == 3)
    }

    @Test func otherMerchantWithSameAmountMarksPossibleDuplicate() throws {
        let context = try makeContext()
        let setup = makeStatement(rows: [makeRow("01.08.2026", "Операция оплаты у коммерсанта ARBUZ", operationAmount: -700, expense: -700)])
        _ = try importStatement(setup, mode: .initialHistory, context: context, now: importedAt)
        let account = try #require(try context.fetch(FetchDescriptor<Account>()).first)
        let applePay = addApplePayEntry(account: account, context: context)
        let statement = makeStatement(rows: [makeRow("12.08.2026", "Операция оплаты у коммерсанта SMALL.KASSA1", operationAmount: -1500, expense: -1500)])

        let result = try importStatement(statement, mode: .regular, context: context, now: importedAt)

        #expect(result.addedCount == 1)
        #expect(result.attachedCount == 0)
        let added = try findEntry(titled: "Small", in: context)
        #expect(added.possibleDuplicateOf === applePay)
        #expect(!added.isReviewed)
    }
}

// Реальная выписка содержит личные данные и в git не попадает, поэтому без неё тест выключен.
@Suite struct ImporterAcceptanceTests {
    @Test(.disabled(if: findRealStatementURL() == nil, "Нет Fixtures/halyk-2026.pdf"))
    func importsRealStatementTwiceWithoutDuplicates() throws {
        let fileURL = try #require(findRealStatementURL())
        let statement = try readStatement(lines: try readTextLines(pdfData: try Data(contentsOf: fileURL)))
        let context = ModelContext(try makeModelContainer(inMemory: true))
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let firstResult = try importStatement(statement, mode: .initialHistory, context: context, now: now)
        let account = try #require(try context.fetch(FetchDescriptor<Account>()).first)
        account.anchorDay = statement.header.generatedOn
        try context.save()
        let secondResult = try importStatement(statement, mode: .regular, context: context, now: now)

        #expect(firstResult.addedCount == 1160)
        #expect(secondResult.addedCount == 0)
        #expect(secondResult.alreadyKnownCount == 1160)
        try printCategoryCounts(context: context)
    }

    // Не проверка, а отчёт для сверки с историей пользователя.
    private func printCategoryCounts(context: ModelContext) throws {
        let entries = try context.fetch(FetchDescriptor<JournalEntry>())
        let countByCategory = Dictionary(grouping: entries) { entry in entry.categoryId ?? "nil" }
            .mapValues { group in group.count }
            .sorted { first, second in first.value > second.value }
        print("IMPORT-REPORT categories:", countByCategory.map { pair in "\(pair.key)=\(pair.value)" }.joined(separator: ", "))
        let transfers = entries.filter { entry in
            entry.sources.contains { source in detectOperationKind(description: source.rawDescription ?? "") == .transferToOtherCard }
        }
        print("IMPORT-REPORT transfers to other card:", transfers.count)
        let familySized = transfers.filter { entry in entry.amount == 100_000 || entry.amount == 120_000 }
        let installmentSized = transfers.filter { entry in entry.amount >= 53_500 && entry.amount <= 54_500 }
        print("IMPORT-REPORT family-sized:", familySized.count, "family:", familySized.filter { entry in entry.categoryId == "family" }.count, "own Kaspi:", familySized.filter { entry in entry.categoryId == "ownTransfer" }.count)
        print("IMPORT-REPORT installment-sized:", installmentSized.count, "installments:", installmentSized.filter { entry in entry.categoryId == "installments" }.count, "own Kaspi:", installmentSized.filter { entry in entry.categoryId == "ownTransfer" }.count)
        print("IMPORT-REPORT own Kaspi:", entries.filter { entry in entry.title == "На свою карту Kaspi" }.count)
        print("IMPORT-REPORT accounts:", try context.fetch(FetchDescriptor<Account>()).map { account in "\(account.kind.rawValue):\(account.title)" })
        print("IMPORT-REPORT non-positive amounts:", entries.filter { entry in entry.amount <= 0 }.count, "negative fees:", entries.filter { entry in entry.feeAmount < 0 }.count)
        print("IMPORT-REPORT needs review:", entries.filter { entry in !entry.isReviewed }.count)
    }
}

private func findRealStatementURL() -> URL? {
    Bundle.module.url(forResource: "halyk-2026", withExtension: "pdf", subdirectory: "Fixtures")
}
