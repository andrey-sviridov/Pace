import Foundation
import SwiftData

public enum RealtimeError: Error, Equatable {
    case sourceWithoutEntry(key: String)
}

/// Записывает операцию Apple Pay или SMS в журнал: присоединяет к найденной записи или создаёт новую.
/// Повтор той же операции (тот же ключ источника) возвращает уже записанную запись.
public func recordRealtimeOperation(
    kind: SourceKind,
    day: CalendarDay,
    time: Date,
    type: EntryType,
    amount: Decimal,
    rawMerchant: String,
    rawText: String?,
    account: Account,
    rules: [MerchantRule],
    salaryHistory: [Decimal],
    context: ModelContext,
    now: Date
) throws -> JournalEntry {
    let merchantKey = makeMerchantKey(rawMerchant)
    let sourceKey = "\(kind.rawValue):\(ISO8601DateFormatter().string(from: time)):\(amount):\(merchantKey)"

    if let existingSource = try findSource(key: sourceKey, context: context) {
        guard let entry = existingSource.entry else { throw RealtimeError.sourceWithoutEntry(key: sourceKey) }
        return entry
    }

    let incoming = IncomingOperation(kind: kind, day: day, time: time, type: type, amount: amount, merchantKey: merchantKey)
    let candidates = try loadAccountEntries(of: account, context: context)
    let match = findMatchingEntry(for: incoming, candidates: candidates, realtimeWindowMinutes: 10, statementWindowDays: 3)

    let source = SourceRecord(
        kind: kind,
        key: sourceKey,
        receivedAt: now,
        operationDay: day,
        rawDescription: rawMerchant,
        operationAmount: amount,
        currency: "KZT",
        rawText: rawText
    )

    do {
        let entry = try makeOrFindEntry(
            match: match,
            incoming: incoming,
            rawMerchant: rawMerchant,
            account: account,
            rules: rules,
            salaryHistory: salaryHistory,
            context: context,
            now: now
        )
        entry.sources.append(source)
        try context.save()
        return entry
    } catch {
        // Без отката в контексте осталась бы полузаписанная операция, и следующий save её сохранил бы.
        context.rollback()
        throw error
    }
}

private func makeOrFindEntry(
    match: MatchResult,
    incoming: IncomingOperation,
    rawMerchant: String,
    account: Account,
    rules: [MerchantRule],
    salaryHistory: [Decimal],
    context: ModelContext,
    now: Date
) throws -> JournalEntry {
    switch match {
    case .attach(let entry):
        return entry
    case .possibleDuplicate(let other):
        let entry = makeRealtimeEntry(incoming, rawMerchant: rawMerchant, account: account, rules: rules, salaryHistory: salaryHistory, now: now)
        entry.possibleDuplicateOf = other
        context.insert(entry)
        return entry
    case .noMatch:
        let entry = makeRealtimeEntry(incoming, rawMerchant: rawMerchant, account: account, rules: rules, salaryHistory: salaryHistory, now: now)
        context.insert(entry)
        return entry
    }
}

private func makeRealtimeEntry(
    _ incoming: IncomingOperation,
    rawMerchant: String,
    account: Account,
    rules: [MerchantRule],
    salaryHistory: [Decimal],
    now: Date
) -> JournalEntry {
    let isSalary = incoming.type == .income
        && isSalaryAmount(incoming.amount, salaryHistory: salaryHistory, minShareOfMedian: Decimal(string: "0.5")!)
    let categoryId = isSalary ? "salary" : findCategoryId(merchantKey: incoming.merchantKey, rules: rules)

    return JournalEntry(
        day: incoming.day,
        time: incoming.time,
        type: incoming.type,
        amount: incoming.amount,
        account: account,
        title: makeRealtimeTitle(rawMerchant: rawMerchant, type: incoming.type),
        merchantKey: incoming.merchantKey,
        categoryId: categoryId,
        isReviewed: false,
        affectsBalance: true,
        createdAt: now
    )
}

/// Крупное поступление, похожее на прошлые зарплаты: бюджет не считает его доходом, но ждёт прогнозную зарплату.
private func isSalaryAmount(_ amount: Decimal, salaryHistory: [Decimal], minShareOfMedian: Decimal) -> Bool {
    guard !salaryHistory.isEmpty else { return false }
    return amount >= calculateMedian(salaryHistory) * minShareOfMedian
}

/// У поступления из SMS продавца часто нет, поэтому название берём по типу операции.
private func makeRealtimeTitle(rawMerchant: String, type: EntryType) -> String {
    guard rawMerchant.trimmingCharacters(in: .whitespaces).isEmpty else { return makeTitle(merchant: rawMerchant) }
    return type == .income ? "Поступление" : "Платёж"
}

private func findSource(key: String, context: ModelContext) throws -> SourceRecord? {
    let descriptor = FetchDescriptor<SourceRecord>(predicate: #Predicate { source in source.key == key })
    return try context.fetch(descriptor).first
}

/// Записи счёта с любой стороны перемещения; слитые отсеивает сам поиск совпадений.
private func loadAccountEntries(of account: Account, context: ModelContext) throws -> [JournalEntry] {
    let entries = try context.fetch(FetchDescriptor<JournalEntry>())
    return entries.filter { entry in
        entry.account?.persistentModelID == account.persistentModelID
            || entry.counterAccount?.persistentModelID == account.persistentModelID
    }
}
