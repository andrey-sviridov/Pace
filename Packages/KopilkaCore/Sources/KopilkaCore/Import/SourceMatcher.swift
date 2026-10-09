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

/// Сливает две записи вручную: источники переезжают в `keep`, `remove` остаётся скрытой,
/// чтобы её ключи продолжали ловить дубли (удаление каскадом стёрло бы источники).
public func mergeEntries(keep: JournalEntry, remove: JournalEntry) {
    for source in remove.sources {
        source.entry = keep
    }
    remove.mergedInto = keep
    if keep.possibleDuplicateOf === remove {
        keep.possibleDuplicateOf = nil
    }
}

private func hasSource(_ entry: JournalEntry, kind: SourceKind) -> Bool {
    entry.sources.contains { source in source.kind == kind }
}

/// Время есть у обеих сторон (Apple Pay, SMS) — сравниваем минуты, иначе только дни.
private func isWithinTime(_ entry: JournalEntry, incoming: IncomingOperation, realtimeWindowMinutes: Int, statementWindowDays: Int) -> Bool {
    if let entryTime = entry.time, let incomingTime = incoming.time {
        let minutesApart = abs(entryTime.timeIntervalSince(incomingTime)) / 60
        return minutesApart <= Double(realtimeWindowMinutes)
    }
    return abs(entry.day.daysUntil(incoming.day)) <= statementWindowDays
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
