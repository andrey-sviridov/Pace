import Foundation
import SwiftData

public enum BackupError: Error, Equatable {
    case unsupportedVersion(Int)
    case danglingReference(String)
}

/// Вся база одним JSON-файлом.
public func makeBackup(context: ModelContext) throws -> Data {
    let accounts = try context.fetch(FetchDescriptor<Account>())
    let accountIndexes = makeAccountIndexes(accounts)

    let file = BackupFile(
        version: BackupFile.currentVersion,
        accounts: accounts.map(makeAccountBackup),
        categories: try context.fetch(FetchDescriptor<SpendingCategory>()).map(makeCategoryBackup),
        merchantRules: try context.fetch(FetchDescriptor<MerchantRule>()).map(makeMerchantRuleBackup),
        amountRules: try context.fetch(FetchDescriptor<AmountRule>()).map(makeAmountRuleBackup),
        settings: try context.fetch(FetchDescriptor<AppSettings>()).map(makeSettingsBackup),
        entries: try context.fetch(FetchDescriptor<JournalEntry>()).map { entry in makeEntryBackup(entry, accountIndexes: accountIndexes) },
        sources: try context.fetch(FetchDescriptor<SourceRecord>()).map(makeSourceBackup)
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(file)
}

/// Полная замена данных копией из файла. Единственное место, где база стирается целиком, — восстановление,
/// которое пользователь подтвердил. Файл разбирается и проверяется до первого удаления.
public func restoreBackup(_ data: Data, context: ModelContext) throws {
    try restoreBackup(data, context: context, afterDelete: {})
}

/// `afterDelete` выполняется внутри транзакции сразу после удаления: тест с его помощью проверяет откат.
func restoreBackup(_ data: Data, context: ModelContext, afterDelete: () throws -> Void) throws {
    let file = try JSONDecoder().decode(BackupFile.self, from: data)
    try checkBackup(file)

    do {
        try context.transaction {
            try deleteAllData(context: context)
            try afterDelete()
            insertBackup(file, context: context)
        }
    } catch {
        // transaction при ошибке не откатывает контекст, и следующий save записал бы полвосстановления.
        context.rollback()
        throw error
    }
}

// MARK: - Проверка файла

private func checkBackup(_ file: BackupFile) throws {
    guard file.version == BackupFile.currentVersion else { throw BackupError.unsupportedVersion(file.version) }

    let entryIds = Set(file.entries.map { entry in entry.id })
    let accountCount = file.accounts.count
    for entry in file.entries {
        let accountIndexes = [entry.accountIndex, entry.counterAccountIndex].compactMap { index in index }
        guard accountIndexes.allSatisfy({ index in index >= 0 && index < accountCount }) else {
            throw BackupError.danglingReference("счёт записи \(entry.id)")
        }
        let linkedIds = [entry.possibleDuplicateOfId, entry.mergedIntoId].compactMap { id in id }
        guard linkedIds.allSatisfy({ id in entryIds.contains(id) }) else {
            throw BackupError.danglingReference("связанная запись \(entry.id)")
        }
    }
    for source in file.sources {
        guard let entryId = source.entryId else { continue }
        guard entryIds.contains(entryId) else { throw BackupError.danglingReference("запись источника \(source.key)") }
    }
}

// MARK: - Восстановление

/// «Начать заново»: стирает всё, пользователь подтвердил дважды. Либо стирается всё, либо ничего.
public func eraseAllData(context: ModelContext) throws {
    do {
        try context.transaction {
            try deleteAllData(context: context)
        }
        try context.save()
    } catch {
        context.rollback()
        throw error
    }
}

private func deleteAllData(context: ModelContext) throws {
    // Источники удаляем до записей: двойное удаление через каскад ломает rollback (SwiftData падает при откате).
    for source in try context.fetch(FetchDescriptor<SourceRecord>()) { context.delete(source) }
    for entry in try context.fetch(FetchDescriptor<JournalEntry>()) { context.delete(entry) }
    for account in try context.fetch(FetchDescriptor<Account>()) { context.delete(account) }
    for category in try context.fetch(FetchDescriptor<SpendingCategory>()) { context.delete(category) }
    for rule in try context.fetch(FetchDescriptor<MerchantRule>()) { context.delete(rule) }
    for rule in try context.fetch(FetchDescriptor<AmountRule>()) { context.delete(rule) }
    for settings in try context.fetch(FetchDescriptor<AppSettings>()) { context.delete(settings) }
}

private func insertBackup(_ file: BackupFile, context: ModelContext) {
    let accounts = file.accounts.map(makeAccount)
    accounts.forEach { account in context.insert(account) }
    file.categories.map(makeCategory).forEach { category in context.insert(category) }
    file.merchantRules.map(makeMerchantRule).forEach { rule in context.insert(rule) }
    file.amountRules.map(makeAmountRule).forEach { rule in context.insert(rule) }
    file.settings.map(makeSettings).forEach { settings in context.insert(settings) }

    let entriesById = insertEntries(file.entries, accounts: accounts, context: context)
    for sourceBackup in file.sources {
        let source = makeSource(sourceBackup)
        context.insert(source)
        source.entry = sourceBackup.entryId.flatMap { id in entriesById[id] }
    }
}

private func insertEntries(_ backups: [EntryBackup], accounts: [Account], context: ModelContext) -> [UUID: JournalEntry] {
    var entriesById: [UUID: JournalEntry] = [:]
    for backup in backups {
        let entry = makeEntry(backup, accounts: accounts)
        context.insert(entry)
        entriesById[backup.id] = entry
    }
    // Ссылки между записями — вторым проходом, когда все записи уже существуют.
    for backup in backups {
        entriesById[backup.id]?.possibleDuplicateOf = backup.possibleDuplicateOfId.flatMap { id in entriesById[id] }
        entriesById[backup.id]?.mergedInto = backup.mergedIntoId.flatMap { id in entriesById[id] }
    }
    return entriesById
}

// MARK: - Модель в копию

private func makeAccountIndexes(_ accounts: [Account]) -> [PersistentIdentifier: Int] {
    Dictionary(uniqueKeysWithValues: accounts.enumerated().map { index, account in (account.persistentModelID, index) })
}

private func makeAccountBackup(_ account: Account) -> AccountBackup {
    AccountBackup(kind: account.kind, title: account.title, number: account.number, anchorBalance: account.anchorBalance, anchorDay: account.anchorDay)
}

private func makeCategoryBackup(_ category: SpendingCategory) -> CategoryBackup {
    CategoryBackup(
        id: category.id, name: category.name, iconName: category.iconName, kind: category.kind,
        monthlyLimit: category.monthlyLimit, expectedMonthlyAmount: category.expectedMonthlyAmount,
        warnAtPercent: category.warnAtPercent, sortOrder: category.sortOrder
    )
}

private func makeMerchantRuleBackup(_ rule: MerchantRule) -> MerchantRuleBackup {
    MerchantRuleBackup(merchantKey: rule.merchantKey, categoryId: rule.categoryId, title: rule.title, isBuiltIn: rule.isBuiltIn)
}

private func makeAmountRuleBackup(_ rule: AmountRule) -> AmountRuleBackup {
    AmountRuleBackup(
        minAmount: rule.minAmount, maxAmount: rule.maxAmount, afterEvent: rule.afterEvent, windowDays: rule.windowDays,
        beforeDay: rule.beforeDay, categoryId: rule.categoryId, targetAccountKind: rule.targetAccountKind, sortOrder: rule.sortOrder
    )
}

private func makeSettingsBackup(_ settings: AppSettings) -> SettingsBackup {
    SettingsBackup(
        theme: settings.theme, periodMode: settings.periodMode, employerName: settings.employerName,
        kaspiOwnCardUntil: settings.kaspiOwnCardUntil, isApplePayEnabled: settings.isApplePayEnabled,
        isSmsEnabled: settings.isSmsEnabled, shouldShowRemainingAfterPayment: settings.shouldShowRemainingAfterPayment,
        monthlySavingsGoal: settings.monthlySavingsGoal, hasFinishedSetup: settings.hasFinishedSetup,
        hasAdvance: settings.hasAdvance, shouldShowOperationTime: settings.shouldShowOperationTime
    )
}

private func makeEntryBackup(_ entry: JournalEntry, accountIndexes: [PersistentIdentifier: Int]) -> EntryBackup {
    EntryBackup(
        id: entry.id, day: entry.day, time: entry.time, type: entry.type, amount: entry.amount, feeAmount: entry.feeAmount,
        accountIndex: entry.account.flatMap { account in accountIndexes[account.persistentModelID] },
        counterAccountIndex: entry.counterAccount.flatMap { account in accountIndexes[account.persistentModelID] },
        title: entry.title, merchantKey: entry.merchantKey, categoryId: entry.categoryId, note: entry.note,
        isReviewed: entry.isReviewed, possibleDuplicateOfId: entry.possibleDuplicateOf?.id, mergedIntoId: entry.mergedInto?.id,
        affectsBalance: entry.affectsBalance, createdAt: entry.createdAt
    )
}

private func makeSourceBackup(_ source: SourceRecord) -> SourceBackup {
    SourceBackup(
        kind: source.kind, key: source.key, operationDay: source.operationDay, processingDay: source.processingDay,
        rawDescription: source.rawDescription, operationAmount: source.operationAmount, currency: source.currency,
        incomeAmount: source.incomeAmount, expenseAmount: source.expenseAmount, feeAmount: source.feeAmount,
        cardOrAccount: source.cardOrAccount, rawText: source.rawText, receivedAt: source.receivedAt, entryId: source.entry?.id
    )
}

// MARK: - Копия в модель

private func makeAccount(_ backup: AccountBackup) -> Account {
    Account(kind: backup.kind, title: backup.title, number: backup.number, anchorBalance: backup.anchorBalance, anchorDay: backup.anchorDay)
}

private func makeCategory(_ backup: CategoryBackup) -> SpendingCategory {
    SpendingCategory(
        id: backup.id, name: backup.name, iconName: backup.iconName, kind: backup.kind,
        monthlyLimit: backup.monthlyLimit, expectedMonthlyAmount: backup.expectedMonthlyAmount,
        warnAtPercent: backup.warnAtPercent, sortOrder: backup.sortOrder
    )
}

private func makeMerchantRule(_ backup: MerchantRuleBackup) -> MerchantRule {
    MerchantRule(merchantKey: backup.merchantKey, categoryId: backup.categoryId, title: backup.title, isBuiltIn: backup.isBuiltIn)
}

private func makeAmountRule(_ backup: AmountRuleBackup) -> AmountRule {
    AmountRule(
        minAmount: backup.minAmount, maxAmount: backup.maxAmount, afterEvent: backup.afterEvent, windowDays: backup.windowDays,
        beforeDay: backup.beforeDay, categoryId: backup.categoryId, targetAccountKind: backup.targetAccountKind, sortOrder: backup.sortOrder
    )
}

private func makeSettings(_ backup: SettingsBackup) -> AppSettings {
    AppSettings(
        theme: backup.theme, periodMode: backup.periodMode, employerName: backup.employerName,
        kaspiOwnCardUntil: backup.kaspiOwnCardUntil, isApplePayEnabled: backup.isApplePayEnabled,
        isSmsEnabled: backup.isSmsEnabled, shouldShowRemainingAfterPayment: backup.shouldShowRemainingAfterPayment,
        monthlySavingsGoal: backup.monthlySavingsGoal, hasFinishedSetup: backup.hasFinishedSetup,
        hasAdvance: backup.hasAdvance ?? true, shouldShowOperationTime: backup.shouldShowOperationTime ?? true
    )
}

private func makeEntry(_ backup: EntryBackup, accounts: [Account]) -> JournalEntry {
    JournalEntry(
        id: backup.id, day: backup.day, time: backup.time, type: backup.type, amount: backup.amount, feeAmount: backup.feeAmount,
        account: backup.accountIndex.map { index in accounts[index] },
        counterAccount: backup.counterAccountIndex.map { index in accounts[index] },
        title: backup.title, merchantKey: backup.merchantKey, categoryId: backup.categoryId, note: backup.note,
        isReviewed: backup.isReviewed, affectsBalance: backup.affectsBalance, createdAt: backup.createdAt
    )
}

private func makeSource(_ backup: SourceBackup) -> SourceRecord {
    SourceRecord(
        kind: backup.kind, key: backup.key, receivedAt: backup.receivedAt, operationDay: backup.operationDay,
        processingDay: backup.processingDay, rawDescription: backup.rawDescription, operationAmount: backup.operationAmount,
        currency: backup.currency, incomeAmount: backup.incomeAmount, expenseAmount: backup.expenseAmount,
        feeAmount: backup.feeAmount, cardOrAccount: backup.cardOrAccount, rawText: backup.rawText
    )
}
