import Foundation

/// Накопленные траты к концу дня: все и отдельно обязательные.
public struct DailySpending: Equatable, Sendable {
    public let day: CalendarDay
    public let total: Decimal
    public let obligatoryTotal: Decimal
}

public struct CategorySpending: Equatable, Sendable {
    public let categoryId: String
    public let total: Decimal
}

public struct PeriodLeftover: Equatable, Sendable {
    public let period: Period
    /// Доход минус траты; минус — потратили больше, чем пришло.
    public let leftover: Decimal
}

/// Накопленные траты по дням периода: до сегодня, если период текущий, иначе весь период.
public func calculateCumulativeSpending(period: Period, today: CalendarDay, entries: [JournalEntry], categories: [SpendingCategory]) -> [DailySpending] {
    let kindsById = makeCategoryKindsById(categories)
    let periodEntries = findPeriodEntries(entries, period: period)
    let shownDays = period.contains(today) ? period.days.filter { day in day <= today } : period.days

    var total: Decimal = 0
    var obligatoryTotal: Decimal = 0
    return shownDays.map { day in
        let dayEntries = periodEntries.filter { entry in entry.day == day }
        total += calculateSpending(of: dayEntries, kinds: [.obligatory, .flexible], kindsById: kindsById)
        obligatoryTotal += calculateSpending(of: dayEntries, kinds: [.obligatory], kindsById: kindsById)
        return DailySpending(day: day, total: total, obligatoryTotal: obligatoryTotal)
    }
}

/// Траты периода по категориям, только положительные, от больших к меньшим.
public func calculateSpendingByCategory(period: Period, entries: [JournalEntry], categories: [SpendingCategory]) -> [CategorySpending] {
    let kindsById = makeCategoryKindsById(categories)
    let periodEntries = findPeriodEntries(entries, period: period)

    let parts = periodEntries.flatMap { entry in makeSpendingParts(of: entry, kindsById: kindsById) }
    var totalsByCategoryId: [String: Decimal] = [:]
    for part in parts {
        totalsByCategoryId[part.categoryId, default: 0] += part.amount
    }

    return totalsByCategoryId
        .filter { categoryId, total in total > 0 }
        .map { categoryId, total in CategorySpending(categoryId: categoryId, total: total) }
        .sorted { first, second in first.total > second.total }
}

/// Сколько осталось в каждом периоде: фактический доход − фактические обязательные и гибкие траты.
public func calculateMonthlyLeftover(months: [Period], entries: [JournalEntry], categories: [SpendingCategory]) -> [PeriodLeftover] {
    let kindsById = makeCategoryKindsById(categories)
    return months.map { month in
        let monthEntries = findPeriodEntries(entries, period: month)
        let income = calculateActualIncome(of: monthEntries, kindsById: kindsById)
        let spending = calculateSpending(of: monthEntries, kinds: [.obligatory, .flexible], kindsById: kindsById)
        return PeriodLeftover(period: month, leftover: income - spending)
    }
}

/// Траты одной категории по каждому периоду, в том же порядке, что и `periods`.
public func calculateCategoryHistory(categoryId: String, periods: [Period], entries: [JournalEntry], categories: [SpendingCategory]) -> [Decimal] {
    let kindsById = makeCategoryKindsById(categories)
    return periods.map { period in
        calculateCategorySpending(categoryId: categoryId, entries: findPeriodEntries(entries, period: period), kindsById: kindsById)
    }
}
