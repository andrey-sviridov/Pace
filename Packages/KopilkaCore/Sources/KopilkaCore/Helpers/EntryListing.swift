import Foundation

// Порядок и группировка записей для списков «Проверьте новое» и «Журнал», подбор записи для ручной склейки.

/// Новые дни сверху; внутри дня — в порядке добавления, сначала последние.
public func isShownEarlier(_ first: JournalEntry, than second: JournalEntry) -> Bool {
    guard first.day == second.day else { return first.day > second.day }
    return first.createdAt > second.createdAt
}

/// Записи одного дня для секции списка.
public struct DayGroup: Identifiable {
    public let day: CalendarDay
    public let entries: [JournalEntry]

    public var id: CalendarDay { day }
}

/// Группы по дням, новые дни сверху. Порядок внутри дня — как у `isShownEarlier`.
public func makeDayGroups(_ entries: [JournalEntry]) -> [DayGroup] {
    let sortedEntries = entries.sorted { first, second in isShownEarlier(first, than: second) }
    var groups: [DayGroup] = []
    for entry in sortedEntries {
        if let lastGroup = groups.last, lastGroup.day == entry.day {
            groups[groups.count - 1] = DayGroup(day: lastGroup.day, entries: lastGroup.entries + [entry])
        } else {
            groups.append(DayGroup(day: entry.day, entries: [entry]))
        }
    }
    return groups
}

/// Кандидаты для «Это та же операция, что…»: видимые записи того же типа, с близкой суммой (до 25 %),
/// в пределах `windowDays` от записи. Ближайшие по дате, затем по сумме — сверху.
public func findMergeCandidates(for entry: JournalEntry, among entries: [JournalEntry], windowDays: Int) -> [JournalEntry] {
    let candidates = entries.filter { other in
        other !== entry
            && other.mergedInto == nil
            && other.type == entry.type
            && isCloseAmount(other.amount, entry.amount, maxDifferenceShare: 0.25)
            && abs(entry.day.daysUntil(other.day)) <= windowDays
    }
    return candidates.sorted { first, second in
        let firstDays = abs(entry.day.daysUntil(first.day))
        let secondDays = abs(entry.day.daysUntil(second.day))
        guard firstDays == secondDays else { return firstDays < secondDays }
        return abs(first.amount - entry.amount) < abs(second.amount - entry.amount)
    }
}

/// Суммы Apple Pay и выписки могут расходиться на чаевые или холд — для ручной склейки этого достаточно.
private func isCloseAmount(_ first: Decimal, _ second: Decimal, maxDifferenceShare: Decimal) -> Bool {
    let larger = max(first, second)
    guard larger > 0 else { return first == second }
    return abs(first - second) / larger <= maxDifferenceShare
}

/// «−1 500 ₸» для расхода, «+1 500 ₸» для дохода; перемещение и корректировка — без знака.
public func formatSignedTenge(_ amount: Decimal, type: EntryType) -> String {
    switch type {
    case .expense:
        return "−" + formatTenge(amount)
    case .income:
        return "+" + formatTenge(amount)
    case .transfer, .adjustment:
        return formatTenge(amount)
    }
}

/// «12 окт, пн» — заголовок дня в списках.
public func formatDayWithWeekday(_ day: CalendarDay) -> String {
    let weekdayNames = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
    return "\(formatShortDay(day)), \(weekdayNames[calculateWeekdayIndex(day)])"
}

/// 0 — воскресенье, как у `Calendar.weekday - 1`. Календарь в GMT: нужен только день недели даты, без часовых поясов.
func calculateWeekdayIndex(_ day: CalendarDay) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    let components = DateComponents(year: day.year, month: day.month, day: day.day)
    guard let date = calendar.date(from: components) else {
        preconditionFailure("CalendarDay валиден по построению, Calendar обязан построить дату")
    }
    return calendar.component(.weekday, from: date) - 1
}
