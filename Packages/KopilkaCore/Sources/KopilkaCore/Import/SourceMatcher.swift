import Foundation

/// Новая операция из любого источника, ещё не попавшая в журнал.
public struct IncomingOperation {
    public let kind: SourceKind
    public let day: CalendarDay
    /// Есть только у Apple Pay и SMS.
    public let time: Date?
    public let type: EntryType
    public let amount: Decimal
    public let merchantKey: String

    public init(kind: SourceKind, day: CalendarDay, time: Date?, type: EntryType, amount: Decimal, merchantKey: String) {
        self.kind = kind
        self.day = day
        self.time = time
        self.type = type
        self.amount = amount
        self.merchantKey = merchantKey
    }
}

public enum MatchResult {
    case attach(to: JournalEntry)
    case possibleDuplicate(of: JournalEntry)
    case noMatch
}

/// Правила спеки §5.6: ищем среди записей, у которых ещё нет источника этого типа.
public func findMatchingEntry(
    for incoming: IncomingOperation,
    candidates: [JournalEntry],
    realtimeWindowMinutes: Int,
    statementWindowDays: Int
) -> MatchResult {
    let withoutSameSource = candidates.filter { entry in
        entry.mergedInto == nil && !hasSource(entry, kind: incoming.kind)
    }
    // Возврат на ту же сумму не должен склеиться с покупкой: направление денег обязано совпасть.
    let sameType = withoutSameSource.filter { entry in entry.type == incoming.type }
    let sameAmount = sameType.filter { entry in entry.amount == incoming.amount }
    let withinTime = sameAmount.filter { entry in
        isWithinTime(entry, incoming: incoming, realtimeWindowMinutes: realtimeWindowMinutes, statementWindowDays: statementWindowDays)
    }
    let compatibleMerchant = withinTime.filter { entry in
        isMerchantCompatible(entry.merchantKey, incoming.merchantKey)
    }

    if let nearest = findNearest(to: incoming, in: compatibleMerchant) {
        return .attach(to: nearest)
    }
    if let nearest = findNearest(to: incoming, in: withinTime) {
        return .possibleDuplicate(of: nearest)
    }
    return .noMatch
}

/// Почему ручную склейку нельзя выполнить. Экран показывает это как ошибку: кнопки не должны были её допустить.
public enum MergeError: Error, Equatable {
    case sameEntry
    case entryAlreadyMerged
}

/// Сливает две записи вручную: источники переезжают в `keep`, `remove` остаётся скрытой,
/// чтобы её ключи продолжали ловить дубли (удаление каскадом стёрло бы источники).
/// `allEntries` нужны, чтобы найти записи, раньше склеенные в `remove`: они переводятся на `keep`,
/// иначе цепочка вела бы к скрытой записи.
public func mergeEntries(keep: JournalEntry, remove: JournalEntry, allEntries: [JournalEntry]) throws {
    guard keep !== remove else { throw MergeError.sameEntry }
    guard keep.mergedInto == nil, remove.mergedInto == nil else { throw MergeError.entryAlreadyMerged }

    // Смотрим до переноса источников: потом у `remove` их уже не будет.
    let isStatementAmountOnRemoved = hasSource(remove, kind: .statement) && !hasSource(keep, kind: .statement)

    for source in remove.sources {
        source.entry = keep
    }
    // Сумма выписки точнее (чаевые, холд, конвертация валюты): если она у склеиваемой записи — берём её.
    if isStatementAmountOnRemoved {
        keep.amount = remove.amount
    }
    // Комиссию знает только выписка: если её принёс второй источник, без переноса остаток разошёлся бы на сумму комиссии.
    if remove.feeAmount > 0 && keep.feeAmount == 0 {
        keep.feeAmount = remove.feeAmount
    }
    let entriesMergedIntoRemove = allEntries.filter { entry in entry.mergedInto === remove }
    for entry in entriesMergedIntoRemove {
        entry.mergedInto = keep
    }
    remove.mergedInto = keep
    if keep.possibleDuplicateOf === remove {
        keep.possibleDuplicateOf = nil
    }
}

/// Видимая запись, в которую в итоге склеена `entry` (или сама `entry`, если она не склеена).
public func findMergeRoot(_ entry: JournalEntry) -> JournalEntry {
    var root = entry
    while let next = root.mergedInto {
        root = next
    }
    return root
}

private func hasSource(_ entry: JournalEntry, kind: SourceKind) -> Bool {
    entry.sources.contains { source in source.kind == kind }
}

/// Время есть у обеих сторон (Apple Pay, SMS) — сравниваем минуты, иначе только дни.
/// Строка выписки не может быть раньше самой оплаты: банк проводит операцию в тот же день или позже.
/// Без этого ежедневный кофе сегодня прилипал бы к вчерашней строке выписки, и сегодняшняя трата пропадала.
private func isWithinTime(_ entry: JournalEntry, incoming: IncomingOperation, realtimeWindowMinutes: Int, statementWindowDays: Int) -> Bool {
    if let entryTime = entry.time, let incomingTime = incoming.time {
        let minutesApart = abs(entryTime.timeIntervalSince(incomingTime)) / 60
        return minutesApart <= Double(realtimeWindowMinutes)
    }
    let isIncomingFromStatement = incoming.kind == .statement
    let paymentDay = isIncomingFromStatement ? entry.day : incoming.day
    let statementDay = isIncomingFromStatement ? incoming.day : entry.day
    let daysFromPaymentToStatement = paymentDay.daysUntil(statementDay)
    return daysFromPaymentToStatement >= 0 && daysFromPaymentToStatement <= statementWindowDays
}

/// У переводов продавца нет, поэтому пустой ключ подходит к любому.
private func isMerchantCompatible(_ first: String, _ second: String) -> Bool {
    first.isEmpty || second.isEmpty || first.contains(second) || second.contains(first)
}

/// При равном расстоянии берём раньше созданную запись.
private func findNearest(to incoming: IncomingOperation, in entries: [JournalEntry]) -> JournalEntry? {
    entries.min { first, second in
        let firstDistance = calculateDistanceMinutes(first, incoming: incoming)
        let secondDistance = calculateDistanceMinutes(second, incoming: incoming)
        guard firstDistance != secondDistance else { return first.createdAt < second.createdAt }
        return firstDistance < secondDistance
    }
}

/// Дни переводим в минуты, чтобы сравнивать записи с временем и без него одной меркой.
private func calculateDistanceMinutes(_ entry: JournalEntry, incoming: IncomingOperation) -> Double {
    if let entryTime = entry.time, let incomingTime = incoming.time {
        return abs(entryTime.timeIntervalSince(incomingTime)) / 60
    }
    return Double(abs(entry.day.daysUntil(incoming.day))) * 24 * 60
}
