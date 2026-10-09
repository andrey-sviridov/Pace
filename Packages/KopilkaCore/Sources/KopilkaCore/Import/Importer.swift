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
    /// Строки, склеенные с уже существующими записями (Apple Pay, SMS); новых записей для них нет.
    public let attachedCount: Int
    public let alreadyKnownCount: Int
    public let needsReviewCount: Int
    public let accountKind: AccountKind
}

/// Импорт выписки в журнал: либо вся выписка, либо ничего (спека §7).
public func importStatement(_ statement: ParsedStatement, mode: ImportMode, context: ModelContext, now: Date) throws -> ImportResult {
    do {
        return try importStatementInTransaction(statement, mode: mode, context: context, now: now)
    } catch {
        // transaction при ошибке не откатывает контекст, и следующий save записал бы полвыписки;
        // rollback сбрасывает и несохранённые правки вызывающего, поэтому перед импортом их сохраняют.
        context.rollback()
        throw error
    }
}

private func importStatementInTransaction(_ statement: ParsedStatement, mode: ImportMode, context: ModelContext, now: Date) throws -> ImportResult {
    var result: ImportResult?
    try context.transaction {
        try checkTotals(statement)
        let account = try findOrCreateStatementAccount(statement, mode: mode, context: context)
        let merchantRules = try loadMerchantRules(context: context)
        let amountRules = try loadAmountRules(context: context)

        let existingKeys = try loadSourceKeys(context: context)
        let keyedRows = makeKeyedRows(rows: statement.rows, accountNumber: statement.header.accountNumber)
        let newRows = findNewRows(keyedRows: keyedRows, existingKeys: existingKeys)
        let kinds = newRows.map { keyedRow in detectOperationKind(description: keyedRow.row.description) }
        let depositAccount = try findOrCreateAccount(kind: .deposit, title: "Депозит", isNeeded: hasDepositMoves(kinds), context: context)

        // Проход 1: собираем записи по строкам (в базу пока не вставляем) и ищем для каждой уже существующую запись из Apple Pay/SMS.
        let builtEntries = zip(newRows, kinds).map { keyedRow, kind in
            makeEntry(
                from: keyedRow,
                kind: kind,
                account: account,
                depositAccount: depositAccount,
                merchantRules: merchantRules,
                mode: mode,
                now: now
            )
        }
        let candidates = try loadMatchCandidates(of: account, context: context)
        let matches = findRowMatches(entries: builtEntries, candidates: candidates)
        let plans = newRows.indices.map { index in
            RowPlan(keyedRow: newRows[index], kind: kinds[index], entry: builtEntries[index], match: matches[index])
        }
        let attachedPlans = plans.filter { plan in findAttachTarget(plan.match) != nil }
        let freshPlans = plans.filter { plan in findAttachTarget(plan.match) == nil }
        attachRows(attachedPlans, receivedAt: now)

        // Остальные строки становятся новыми записями.
        let newEntries = freshPlans.map { plan in plan.entry }
        let freshKinds = freshPlans.map { plan in plan.kind }
        markPossibleDuplicates(freshPlans)
        addEntries(newEntries, rows: freshPlans.map { plan in plan.keyedRow }, context: context, receivedAt: now)

        // Проход 2: правила сумм для переводов на другую карту.
        let salaryEvents = findSalaryEvents(
            entries: try loadEntries(of: account, context: context),
            advanceDayRange: 10...20,
            oneOffAboveMedianTimes: 1.5
        )
        let transfers = zip(newEntries, freshKinds).filter { entry, kind in kind == .transferToOtherCard }.map { entry, kind in entry }
        let transferRules = transfers.map { entry in
            findAmountRule(day: entry.day, amount: entry.amount, rules: amountRules, salaryEvents: salaryEvents)
        }
        let kaspiAccount = try findOrCreateAccount(
            kind: .ownOtherCard,
            title: "Kaspi *3436",
            isNeeded: transferRules.contains { rule in rule?.targetAccountKind == .ownOtherCard },
            context: context
        )
        for (entry, rule) in zip(transfers, transferRules) {
            updateEntry(entry, byAmountRule: rule, ownCardAccount: kaspiAccount)
        }

        try context.save()
        result = ImportResult(
            addedCount: newEntries.count,
            attachedCount: attachedPlans.count,
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
    // Для перемещений: account — откуда ушли деньги, counterAccount — куда пришли.
    var fromAccount: Account? = account
    var counterAccount: Account?
    var merchantKey = ""

    switch kind {
    case .purchase(let merchant) where row.incomeAmount > 0 && row.expenseAmount == 0:
        // Отмена покупки приходит строкой «оплата у коммерсанта» с приходом — это возврат.
        merchantKey = makeMerchantKey(merchant)
        type = .income
        amount = abs(row.incomeAmount)
        categoryId = findCategoryId(merchantKey: merchantKey, rules: merchantRules) ?? "refunds"
        title = makeTitle(merchant: merchant)
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
        fromAccount = depositAccount
        counterAccount = account
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
        account: fromAccount,
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
/// Выписка депозита забирает себе «Депозит» без номера, созданный импортом карты, — иначе остаток раздвоится.
private func findOrCreateStatementAccount(_ statement: ParsedStatement, mode: ImportMode, context: ModelContext) throws -> Account {
    let header = statement.header
    if let account = try findAccount(number: header.accountNumber, context: context) {
        return account
    }
    if isDepositStatement(header), let unnumberedDeposit = try findAccount(kind: .deposit, number: "", context: context) {
        unnumberedDeposit.number = header.accountNumber
        return unnumberedDeposit
    }
    guard mode == .initialHistory else {
        throw ImportError.unknownAccount(number: header.accountNumber)
    }
    let account = makeAccount(header: header, rows: statement.rows)
    context.insert(account)
    return account
}

/// Второй конец перемещения (депозит, своя Kaspi): номера в выписке карты нет, ищем по виду счёта.
/// Не нужен — nil, чтобы не заводить пустой счёт, которого у пользователя нет.
private func findOrCreateAccount(kind: AccountKind, title: String, isNeeded: Bool, context: ModelContext) throws -> Account? {
    guard isNeeded else { return nil }
    let accounts = try context.fetch(FetchDescriptor<Account>())
    if let account = accounts.first(where: { account in account.kind == kind }) {
        return account
    }
    let account = Account(kind: kind, title: title, number: "")
    context.insert(account)
    return account
}

private func findAccount(kind: AccountKind, number: String, context: ModelContext) throws -> Account? {
    let accounts = try context.fetch(FetchDescriptor<Account>())
    return accounts.first { account in account.kind == kind && account.number == number }
}

private func isDepositStatement(_ header: StatementHeader) -> Bool {
    normalizeDescription(header.accountType).contains("ДЕПОЗИТ")
}

private func findAccount(number: String, context: ModelContext) throws -> Account? {
    let descriptor = FetchDescriptor<Account>(predicate: #Predicate { account in account.number == number })
    return try context.fetch(descriptor).first
}

private func makeAccount(header: StatementHeader, rows: [StatementRow]) -> Account {
    guard !isDepositStatement(header) else {
        return Account(kind: .deposit, title: "Депозит", number: header.accountNumber)
    }
    let cardLastDigits = findMainCardNumber(rows: rows)?.suffix(4) ?? header.accountNumber.suffix(4)
    return Account(kind: .card, title: "Карта *\(cardLastDigits)", number: header.accountNumber)
}

/// Карту пользователь знает по маске ("552204******2936"), а не по номеру счёта; берём самую частую.
private func findMainCardNumber(rows: [StatementRow]) -> String? {
    let maskedCards = rows.map { row in row.cardOrAccount }.filter { card in card.contains("*") }
    let countByCard = Dictionary(grouping: maskedCards) { card in card }.mapValues { group in group.count }
    return countByCard.max { first, second in first.value < second.value }?.key
}

private func hasDepositMoves(_ kinds: [OperationKind]) -> Bool {
    kinds.contains { kind in kind == .toDeposit || kind == .fromDeposit }
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

/// Строка выписки с готовой записью и тем, что нашлось среди уже существующих записей.
private struct RowPlan {
    let keyedRow: KeyedRow
    let kind: OperationKind
    let entry: JournalEntry
    let match: MatchResult
}

/// Кандидаты на склейку: записи счёта без источника «выписка», то есть пришедшие из Apple Pay, SMS или вручную.
private func loadMatchCandidates(of account: Account, context: ModelContext) throws -> [JournalEntry] {
    let entries = try loadEntries(of: account, context: context)
    return entries.filter { entry in !entry.sources.contains { source in source.kind == .statement } }
}

/// Строка, присоединённая к записи, больше не кандидат для следующих строк: у записи теперь есть источник «выписка».
private func findRowMatches(entries: [JournalEntry], candidates: [JournalEntry]) -> [MatchResult] {
    var freeCandidates = candidates
    var matches: [MatchResult] = []
    for entry in entries {
        let incoming = IncomingOperation(kind: .statement, day: entry.day, time: nil, type: entry.type, amount: entry.amount, merchantKey: entry.merchantKey)
        let match = findMatchingEntry(for: incoming, candidates: freeCandidates, realtimeWindowMinutes: 10, statementWindowDays: 3)
        if let target = findAttachTarget(match) {
            freeCandidates.removeAll { candidate in candidate === target }
        }
        matches.append(match)
    }
    return matches
}

private func findAttachTarget(_ match: MatchResult) -> JournalEntry? {
    guard case .attach(let target) = match else { return nil }
    return target
}

/// Источник выписки переезжает в существующую запись; сумма и баланс остаются от Apple Pay/SMS, комиссию знает только выписка.
private func attachRows(_ plans: [RowPlan], receivedAt: Date) {
    for plan in plans {
        guard let target = findAttachTarget(plan.match) else { continue }
        target.sources.append(SourceRecord(row: plan.keyedRow.row, key: plan.keyedRow.key, receivedAt: receivedAt))
        if plan.entry.feeAmount > 0 {
            target.feeAmount = plan.entry.feeAmount
        }
    }
}

private func markPossibleDuplicates(_ plans: [RowPlan]) {
    for plan in plans {
        guard case .possibleDuplicate(let other) = plan.match else { continue }
        plan.entry.possibleDuplicateOf = other
        plan.entry.isReviewed = false
    }
}

/// Вставляет записи вместе с их источником-строкой выписки; `entries` и `rows` идут в одном порядке.
private func addEntries(_ entries: [JournalEntry], rows: [KeyedRow], context: ModelContext, receivedAt: Date) {
    for (entry, keyedRow) in zip(entries, rows) {
        context.insert(entry)
        entry.sources = [SourceRecord(row: keyedRow.row, key: keyedRow.key, receivedAt: receivedAt)]
    }
}

/// Записи счёта с любой стороны перемещения, включая только что вставленные (fetch видит несохранённые изменения).
private func loadEntries(of account: Account, context: ModelContext) throws -> [JournalEntry] {
    let entries = try context.fetch(FetchDescriptor<JournalEntry>())
    return entries.filter { entry in
        entry.account?.persistentModelID == account.persistentModelID
            || entry.counterAccount?.persistentModelID == account.persistentModelID
    }
}

/// Нет правила — перевод остаётся «Переводы людям» и ждёт разбора.
private func updateEntry(_ entry: JournalEntry, byAmountRule rule: AmountRule?, ownCardAccount: Account?) {
    guard let rule else { return }

    if rule.targetAccountKind == .ownOtherCard {
        entry.type = .transfer
        entry.categoryId = "ownTransfer"
        entry.title = "На свою карту Kaspi"
        entry.counterAccount = ownCardAccount
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
