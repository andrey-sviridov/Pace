import Foundation
import SwiftData

public enum ImportMode: Sendable {
    /// Начальная история: записи не влияют на остаток (спека §5.9).
    case initialHistory
    case regular
}

public enum ImportError: Error, Equatable {
    case unknownAccount(number: String)
}

public struct ImportResult: Equatable, Sendable {
    public let addedCount: Int
    public let alreadyKnownCount: Int
    public let needsReviewCount: Int
    public let accountKind: AccountKind
}

/// Импорт выписки в журнал: либо вся выписка, либо ничего (спека §7).
public func importStatement(_ statement: ParsedStatement, mode: ImportMode, context: ModelContext, now: Date) throws -> ImportResult {
    do {
        return try importStatementInTransaction(statement, mode: mode, context: context, now: now)
    } catch {
        // transaction при ошибке не сохраняет, но оставляет вставки в контексте: следующий save
        // (или автосохранение mainContext) записал бы половину выписки. Проверено опытом на SwiftData.
        context.rollback()
        throw error
    }
}

private func importStatementInTransaction(_ statement: ParsedStatement, mode: ImportMode, context: ModelContext, now: Date) throws -> ImportResult {
    var result: ImportResult?
    try context.transaction {
        try checkTotals(statement)
        let account = try findOrCreateAccount(header: statement.header, mode: mode, context: context)
        let depositAccount = try findDepositAccount(context: context)
        let merchantRules = try loadMerchantRules(context: context)
        let amountRules = try loadAmountRules(context: context)

        let existingKeys = try loadSourceKeys(context: context)
        let keyedRows = makeKeyedRows(rows: statement.rows, accountNumber: statement.header.accountNumber)
        let newRows = findNewRows(keyedRows: keyedRows, existingKeys: existingKeys)

        // Проход 1: создаём все записи, чтобы правила переводов видели аванс из этого же файла (Ruling 3).
        let newEntries = newRows.map { keyedRow in
            makeEntry(
                from: keyedRow,
                kind: detectOperationKind(description: keyedRow.row.description),
                account: account,
                depositAccount: depositAccount,
                merchantRules: merchantRules,
                mode: mode,
                now: now
            )
        }
        addEntries(newEntries, rows: newRows, context: context, receivedAt: now)

        // Проход 2: правила сумм для переводов на другую карту.
        let salaryEvents = findSalaryEvents(
            entries: try loadEntries(of: account, context: context),
            advanceDayRange: 10...20,
            oneOffAboveMedianTimes: 1.5
        )
        for entry in newEntries where isTransferToOtherCard(entry) {
            let rule = findAmountRule(day: entry.day, amount: entry.amount, rules: amountRules, salaryEvents: salaryEvents)
            updateEntry(entry, byAmountRule: rule)
        }

        try context.save()
        result = ImportResult(
            addedCount: newEntries.count,
            alreadyKnownCount: keyedRows.count - newRows.count,
            needsReviewCount: newEntries.filter { entry in !entry.isReviewed }.count,
            accountKind: account.kind
        )
    }
    guard let result else { preconditionFailure("transaction выполняет блок или бросает ошибку") }
    return result
}

/// Запись журнала по строке выписки. Суммы в записи всегда положительные, направление задаёт `type`.
func makeEntry(
    from keyedRow: KeyedRow,
    kind: OperationKind,
    account: Account,
    depositAccount: Account?,
    merchantRules: [MerchantRule],
    mode: ImportMode,
    now: Date
) -> JournalEntry {
    let row = keyedRow.row
    let rowSum = abs(row.incomeAmount + row.expenseAmount)
    let type: EntryType
    let amount: Decimal
    let categoryId: String?
    let title: String
    var counterAccount: Account?
    var merchantKey = ""

    switch kind {
    case .purchase(let merchant):
        merchantKey = makeMerchantKey(merchant)
        type = .expense
        amount = abs(row.expenseAmount)
        categoryId = findCategoryId(merchantKey: merchantKey, rules: merchantRules)
        title = makeTitle(merchant: merchant)
    case .refund(let merchant):
        merchantKey = makeMerchantKey(merchant)
        type = .income
        amount = abs(row.incomeAmount)
        // Возврат уменьшает траты категории продавца; продавца не узнали — отдельная категория.
        categoryId = findCategoryId(merchantKey: merchantKey, rules: merchantRules) ?? "refunds"
        title = makeTitle(merchant: merchant)
    case .salary:
        type = .income
        amount = row.incomeAmount
        categoryId = "salary"
        title = "Зарплата"
    case .incomingTransfer:
        type = .income
        amount = row.incomeAmount
        categoryId = "incomingTransfers"
        title = "Перевод от человека"
    case .depositInterest:
        type = .income
        amount = row.incomeAmount
        categoryId = "depositInterest"
        title = "Проценты по депозиту"
    case .toDeposit:
        type = .transfer
        amount = rowSum
        categoryId = "ownTransfer"
        title = "На депозит"
        counterAccount = depositAccount
    case .fromDeposit:
        type = .transfer
        amount = rowSum
        categoryId = "ownTransfer"
        title = "С депозита"
        counterAccount = depositAccount
    case .transferToOtherCard:
        // Сумма — «Сумма операции»; комиссия банка спрятана в «Расходе» (спека §5.3).
        type = .expense
        amount = abs(row.operationAmount)
        categoryId = "transfersToPeople"
        title = "Перевод на другую карту"
    case .loanPayment:
        type = .expense
        amount = abs(row.expenseAmount)
        categoryId = "loans"
        title = "Погашение кредита"
    case .mortgagePayment:
        type = .expense
        amount = abs(row.expenseAmount)
        categoryId = "mortgage"
        title = "Ипотека"
    case .internationalTransfer:
        type = .expense
        amount = abs(row.expenseAmount)
        categoryId = nil
        title = "Международный перевод"
    case .monthlyFee:
        // Плата за карту стоит в колонке «Комиссия», она и есть сумма записи.
        type = .expense
        amount = abs(row.feeAmount)
        categoryId = "bankFees"
        title = "Плата за карту"
    case .unknown:
        type = row.incomeAmount > 0 ? .income : .expense
        amount = rowSum
        categoryId = nil
        title = row.description
    }

    return JournalEntry(
        day: row.operationDay,
        type: type,
        amount: amount,
        feeAmount: calculateFeeAmount(row: row, kind: kind),
        account: account,
        counterAccount: counterAccount,
        title: title,
        merchantKey: merchantKey,
        categoryId: categoryId,
        isReviewed: isReviewed(categoryId: categoryId),
        affectsBalance: isAffectingBalance(day: row.operationDay, account: account, mode: mode),
        createdAt: now
    )
}

// MARK: - Шаги импорта

/// В начальной истории неизвестный счёт создаётся, в обычном импорте — ошибка (пользователь решает, что это за счёт).
private func findOrCreateAccount(header: StatementHeader, mode: ImportMode, context: ModelContext) throws -> Account {
    if let account = try findAccount(number: header.accountNumber, context: context) {
        return account
    }
    guard mode == .initialHistory else {
        throw ImportError.unknownAccount(number: header.accountNumber)
    }
    let account = makeAccount(header: header)
    context.insert(account)
    return account
}

private func findAccount(number: String, context: ModelContext) throws -> Account? {
    let descriptor = FetchDescriptor<Account>(predicate: #Predicate { account in account.number == number })
    return try context.fetch(descriptor).first
}

private func findDepositAccount(context: ModelContext) throws -> Account? {
    let accounts = try context.fetch(FetchDescriptor<Account>())
    return accounts.first { account in account.kind == .deposit }
}

private func makeAccount(header: StatementHeader) -> Account {
    let isDeposit = normalizeDescription(header.accountType).contains("ДЕПОЗИТ")
    guard !isDeposit else {
        return Account(kind: .deposit, title: "Депозит", number: header.accountNumber)
    }
    return Account(kind: .card, title: "Карта *\(header.accountNumber.suffix(4))", number: header.accountNumber)
}

/// Пустая таблица — встроенные правила без сохранения: засев базы делает начальная настройка.
private func loadMerchantRules(context: ModelContext) throws -> [MerchantRule] {
    let storedRules = try context.fetch(FetchDescriptor<MerchantRule>())
    guard storedRules.isEmpty else { return storedRules }
    return makeBuiltInMerchantRules()
}

/// Пустая таблица — стартовые правила без сохранения, дата Kaspi из настроек.
private func loadAmountRules(context: ModelContext) throws -> [AmountRule] {
    let storedRules = try context.fetch(FetchDescriptor<AmountRule>())
    guard storedRules.isEmpty else { return storedRules }
    let settings = try context.fetch(FetchDescriptor<AppSettings>()).first
    let kaspiOwnCardUntil = settings?.kaspiOwnCardUntil ?? CalendarDay(year: 2026, month: 3, day: 1)
    return makeDefaultAmountRules(kaspiOwnCardUntil: kaspiOwnCardUntil)
}

/// Все ключи источников из базы: SwiftData не отклоняет дубль ключа, а молча перезаписывает, поэтому отсеиваем заранее.
private func loadSourceKeys(context: ModelContext) throws -> Set<String> {
    let sources = try context.fetch(FetchDescriptor<SourceRecord>())
    return Set(sources.map { source in source.key })
}

/// Вставляет записи вместе с их источником-строкой выписки; `entries` и `rows` идут в одном порядке.
private func addEntries(_ entries: [JournalEntry], rows: [KeyedRow], context: ModelContext, receivedAt: Date) {
    for (entry, keyedRow) in zip(entries, rows) {
        context.insert(entry)
        entry.sources = [SourceRecord(row: keyedRow.row, key: keyedRow.key, receivedAt: receivedAt)]
    }
}

/// Записи счёта, включая только что вставленные (fetch видит несохранённые изменения).
private func loadEntries(of account: Account, context: ModelContext) throws -> [JournalEntry] {
    let entries = try context.fetch(FetchDescriptor<JournalEntry>())
    return entries.filter { entry in entry.account?.persistentModelID == account.persistentModelID }
}

private func isTransferToOtherCard(_ entry: JournalEntry) -> Bool {
    entry.sources.contains { source in
        detectOperationKind(description: source.rawDescription ?? "") == .transferToOtherCard
    }
}

/// Нет правила — перевод остаётся «Переводы людям» и ждёт разбора.
private func updateEntry(_ entry: JournalEntry, byAmountRule rule: AmountRule?) {
    guard let rule else { return }

    if rule.targetAccountKind == .ownOtherCard {
        entry.type = .transfer
        entry.categoryId = "ownTransfer"
        entry.title = "На свою карту Kaspi"
    } else if let categoryId = rule.categoryId {
        entry.categoryId = categoryId
    }
    entry.isReviewed = isReviewed(categoryId: entry.categoryId)
}

// MARK: - Поля записи

/// Колонка «Комиссия» плюс скрытая комиссия перевода на другую карту (`Расход − Сумма операции`).
private func calculateFeeAmount(row: StatementRow, kind: OperationKind) -> Decimal {
    switch kind {
    case .monthlyFee:
        // Вся сумма платы уже стоит в amount, иначе посчитаем её дважды.
        return 0
    case .transferToOtherCard:
        return abs(row.feeAmount) + abs(row.expenseAmount) - abs(row.operationAmount)
    default:
        return abs(row.feeAmount)
    }
}

/// «Переводы людям» — временная категория для переводов без правила, их нужно разобрать.
private func isReviewed(categoryId: String?) -> Bool {
    categoryId != nil && categoryId != "transfersToPeople"
}

/// Спека §5.9: начальная история на остаток не влияет; потом — только операции с точки отсчёта.
private func isAffectingBalance(day: CalendarDay, account: Account, mode: ImportMode) -> Bool {
    guard mode == .regular, let anchorDay = account.anchorDay else { return false }
    return day >= anchorDay
}
