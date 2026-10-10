import Foundation

// Календарь журнала: сколько пришло и сколько потрачено в каждый день месяца.
// Считается по тем же правилам, что главная и аналитика (SpendingRules), поэтому цифры совпадают.

public struct DayTotals: Equatable, Sendable {
    public let income: Decimal
    public let spending: Decimal
}

/// Дни месяца, в которые что-то пришло или потрачено. Дней без движения в словаре нет.
public func calculateDailyTotals(month: Period, entries: [JournalEntry], categories: [SpendingCategory]) -> [CalendarDay: DayTotals] {
    let kindsById = makeCategoryKindsById(categories)
    let monthEntries = findPeriodEntries(entries, period: month)
    let entriesByDay = Dictionary(grouping: monthEntries) { entry in entry.day }

    var totals: [CalendarDay: DayTotals] = [:]
    for (day, dayEntries) in entriesByDay {
        let income = calculateActualIncome(of: dayEntries, kindsById: kindsById)
        let spending = calculateSpending(of: dayEntries, kinds: [.obligatory, .flexible], kindsById: kindsById)
        guard income != 0 || spending != 0 else { continue }
        totals[day] = DayTotals(income: income, spending: spending)
    }
    return totals
}

/// Клетки сетки месяца, неделя с понедельника: сначала пустые клетки до 1-го числа (nil), потом все дни.
public func makeMonthGridCells(month: Period) -> [CalendarDay?] {
    // calculateWeekdayIndex: 0 — воскресенье; в сетке понедельник первый, поэтому сдвигаем.
    let emptyCellCount = (calculateWeekdayIndex(month.start) + 6) % 7
    let emptyCells: [CalendarDay?] = Array(repeating: nil, count: emptyCellCount)
    let dayCells: [CalendarDay?] = month.days.map { day in day }
    return emptyCells + dayCells
}

/// «Сентябрь 2026».
public func formatMonthTitle(_ month: Period) -> String {
    "\(nominativeMonthNames[month.start.month - 1]) \(month.start.year)"
}
