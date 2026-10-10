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

/// Кандидаты для «Это та же операция, что…»: видимые записи с той же суммой в пределах `windowDays` от записи.
/// Ближайшие по дате — сверху.
public func findMergeCandidates(for entry: JournalEntry, among entries: [JournalEntry], windowDays: Int) -> [JournalEntry] {
    let candidates = entries.filter { other in
        other !== entry
            && other.mergedInto == nil
            && other.amount == entry.amount
            && abs(entry.day.daysUntil(other.day)) <= windowDays
    }
    return candidates.sorted { first, second in
        abs(entry.day.daysUntil(first.day)) < abs(entry.day.daysUntil(second.day))
    }
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
    return "\(formatShortDay(day)), \(weekdayNames[findWeekdayIndex(day)])"
}

/// 0 — воскресенье, как у `Calendar.weekday - 1`. Календарь в GMT: нужен только день недели даты, без часовых поясов.
private func findWeekdayIndex(_ day: CalendarDay) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    let components = DateComponents(year: day.year, month: day.month, day: day.day)
    guard let date = calendar.date(from: components) else {
        preconditionFailure("CalendarDay валиден по построению, Calendar обязан построить дату")
    }
    return calendar.component(.weekday, from: date) - 1
}
