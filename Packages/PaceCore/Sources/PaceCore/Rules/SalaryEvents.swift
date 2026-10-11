import Foundation

public struct SalaryEvent: Equatable, Sendable {
    public let day: CalendarDay
    public let amount: Decimal
    public let kind: SalaryEventKind
    /// Разовое крупное поступление: не граница периода, не опора правил и не часть прогноза.
    public let isOneOff: Bool

    public init(day: CalendarDay, amount: Decimal, kind: SalaryEventKind, isOneOff: Bool) {
        self.day = day
        self.amount = amount
        self.kind = kind
        self.isOneOff = isOneOff
    }
}

/// Зарплатные поступления: доход с категорией «salary», не слитый в другую запись (спека §5.4).
public func findSalaryEvents(
    entries: [JournalEntry],
    advanceDayRange: ClosedRange<Int>,
    oneOffAboveMedianTimes: Decimal
) -> [SalaryEvent] {
    let salaryEntries = entries.filter { entry in
        entry.type == .income && entry.categoryId == "salary" && entry.mergedInto == nil
    }
    guard !salaryEntries.isEmpty else { return [] }

    // Медиана считается по всем поступлениям, включая разовые: так она устойчива к одному выбросу.
    let medianAmount = calculateMedian(salaryEntries.map { entry in entry.amount })
    let oneOffThreshold = medianAmount * oneOffAboveMedianTimes

    let events = salaryEntries.map { entry in
        SalaryEvent(
            day: entry.day,
            amount: entry.amount,
            kind: advanceDayRange.contains(entry.day.day) ? .advance : .salary,
            isOneOff: entry.amount > oneOffThreshold
        )
    }
    return events.sorted { first, second in first.day < second.day }
}

/// Ожидаемое следующее поступление: медиана суммы и дня месяца по последним `lookbackCount` обычным поступлениям.
public func predictNextEvent(
    kind: SalaryEventKind,
    after day: CalendarDay,
    history: [SalaryEvent],
    lookbackCount: Int
) -> SalaryEvent? {
    let recentEvents = history
        .filter { event in event.kind == kind && !event.isOneOff && event.day <= day }
        .sorted { first, second in first.day < second.day }
        .suffix(lookbackCount)
    guard !recentEvents.isEmpty else { return nil }

    let expectedAmount = calculateMedian(recentEvents.map { event in event.amount })
    let expectedDayOfMonth = calculateMedian(recentEvents.map { event in Decimal(event.day.day) })
    let nextDay = findFirstDayAfter(day, withDayOfMonth: Int(truncating: expectedDayOfMonth as NSDecimalNumber))
    return SalaryEvent(day: nextDay, amount: expectedAmount, kind: kind, isOneOff: false)
}

func calculateMedian(_ values: [Decimal]) -> Decimal {
    let sortedValues = values.sorted()
    let middle = sortedValues.count / 2
    guard sortedValues.count % 2 == 0 else { return sortedValues[middle] }
    return (sortedValues[middle - 1] + sortedValues[middle]) / 2
}

/// Ближайшая дата строго после `day` с нужным числом месяца; в коротком месяце берётся его последний день.
private func findFirstDayAfter(_ day: CalendarDay, withDayOfMonth dayOfMonth: Int) -> CalendarDay {
    for monthShift in 0...1 {
        let monthIndex = day.year * 12 + (day.month - 1) + monthShift
        let candidate = makeClampedDay(year: monthIndex / 12, month: monthIndex % 12 + 1, dayOfMonth: dayOfMonth)
        if candidate > day { return candidate }
    }
    preconditionFailure("В следующем месяце дата всегда позже исходной")
}

private func makeClampedDay(year: Int, month: Int, dayOfMonth: Int) -> CalendarDay {
    let firstOfMonth = CalendarDay(year: year, month: month, day: 1)
    var lastDayOfMonth = 28
    while firstOfMonth.adding(days: lastDayOfMonth).month == month { lastDayOfMonth += 1 }
    return CalendarDay(year: year, month: month, day: min(dayOfMonth, lastDayOfMonth))
}
