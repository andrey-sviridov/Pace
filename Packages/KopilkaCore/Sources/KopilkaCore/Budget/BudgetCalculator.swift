import Foundation

/// Главная цифра «Можно потратить» и все её слагаемые (спека §5.8).
public struct BudgetSummary: Equatable, Sendable {
    public let incomeTotal: Decimal
    public let obligatoryTotal: Decimal
    public let savingsGoal: Decimal
    public let flexibleSpent: Decimal
    public let freeToSpend: Decimal
    /// Дней до конца периода, сегодня включительно.
    public let daysLeft: Int
    public let perDay: Decimal
}

public enum LimitLevel: Sendable {
    case normal, warning, over
}

public struct LimitStatus {
    public let category: SpendingCategory
    public let limit: Decimal
    public let spent: Decimal
    /// Доля потраченного от лимита: 0.5 — половина, больше 1 — перерасход.
    public let usedShare: Double
    /// Доля прошедших дней периода — метка темпа на полосе.
    public let paceShare: Double
    public let level: LimitLevel
}

// MARK: - Можно потратить

/// Можно потратить = Доход − Σ max(план, факт) обязательных − Цель − Гибкие траты.
public func calculateBudget(
    period: Period,
    today: CalendarDay,
    mode: PeriodMode,
    entries: [JournalEntry],
    categories: [SpendingCategory],
    salaryEvents: [SalaryEvent],
    monthlySavingsGoal: Decimal
) -> BudgetSummary {
    let kindsById = makeCategoryKindsById(categories)
    let periodEntries = findPeriodEntries(entries, period: period)

    let incomeTotal = calculateIncome(period: period, periodEntries: periodEntries, kindsById: kindsById, salaryEvents: salaryEvents)
    let obligatoryTotal = calculateObligatory(period: period, mode: mode, periodEntries: periodEntries, allEntries: entries, categories: categories, kindsById: kindsById)
    let savingsGoal = calculateAmountForPeriod(monthlyAmount: monthlySavingsGoal, mode: mode)
    let flexibleSpent = calculateFlexibleSpent(periodEntries: periodEntries, kindsById: kindsById)
    let freeToSpend = incomeTotal - obligatoryTotal - savingsGoal - flexibleSpent

    let daysLeft = max(1, today.daysUntil(period.endExclusive))
    let perDay = calculatePerDay(freeToSpend: freeToSpend, daysLeft: daysLeft)

    return BudgetSummary(
        incomeTotal: incomeTotal,
        obligatoryTotal: obligatoryTotal,
        savingsGoal: savingsGoal,
        flexibleSpent: flexibleSpent,
        freeToSpend: freeToSpend,
        daysLeft: daysLeft,
        perDay: perDay
    )
}

/// Доход периода = факт + ожидаемые, ещё не пришедшие зарплата и аванс.
func calculateIncome(period: Period, periodEntries: [JournalEntry], kindsById: [String: CategoryKind], salaryEvents: [SalaryEvent]) -> Decimal {
    let actualIncome = calculateActualIncome(of: periodEntries, kindsById: kindsById)
    let expectedIncome = calculateExpectedIncome(period: period, salaryEvents: salaryEvents)
    return actualIncome + expectedIncome
}

/// Прогноз зарплаты и аванса, которые попадают в период, но ещё не пришли.
func calculateExpectedIncome(period: Period, salaryEvents: [SalaryEvent]) -> Decimal {
    // Прогноз строится от дня перед периодом: так поступление, опоздавшее внутри периода, всё ещё ожидается.
    let dayBeforePeriod = period.start.adding(days: -1)
    let expectedEvents = [SalaryEventKind.advance, .salary].compactMap { kind in
        predictNextEvent(kind: kind, after: dayBeforePeriod, history: salaryEvents, lookbackCount: 3)
    }
    let notArrivedEvents = expectedEvents.filter { expected in
        period.contains(expected.day) && !hasArrivedEvent(kind: expected.kind, period: period, salaryEvents: salaryEvents)
    }
    return notArrivedEvents.reduce(Decimal(0)) { total, event in total + event.amount }
}

/// Пришло ли в периоде обычное поступление этого вида; разовая премия зарплату не заменяет.
private func hasArrivedEvent(kind: SalaryEventKind, period: Period, salaryEvents: [SalaryEvent]) -> Bool {
    salaryEvents.contains { event in event.kind == kind && !event.isOneOff && period.contains(event.day) }
}

/// Σ max(план, факт) по обязательным категориям: уже заплаченное сверх плана тоже вычитается.
func calculateObligatory(
    period: Period,
    mode: PeriodMode,
    periodEntries: [JournalEntry],
    allEntries: [JournalEntry],
    categories: [SpendingCategory],
    kindsById: [String: CategoryKind]
) -> Decimal {
    let obligatoryCategories = categories.filter { category in category.kind == .obligatory }
    return obligatoryCategories.reduce(Decimal(0)) { total, category in
        let plannedAmount = calculatePlannedAmount(category: category, period: period, mode: mode, entries: allEntries)
        let spentAmount = calculateCategorySpending(categoryId: category.id, entries: periodEntries, kindsById: kindsById)
        return total + max(plannedAmount, spentAmount)
    }
}

/// План обязательной категории на период: заданная вручную сумма или типичная за 3 месяца.
func calculatePlannedAmount(category: SpendingCategory, period: Period, mode: PeriodMode, entries: [JournalEntry]) -> Decimal {
    let monthlyPlan = category.expectedMonthlyAmount
        ?? calculateTypicalMonthlyAmount(categoryId: category.id, entries: entries, before: period.start, monthCount: 3)
    guard mode == .halfMonth else { return monthlyPlan }

    // Неизвестно, в какую половину платёж: резервируем в обеих, лучше показать меньше, чем внезапный минус.
    guard let lastPaymentDay = findLastPaymentDay(categoryId: category.id, entries: entries, before: period.start) else { return monthlyPlan }
    return hasDayOfMonth(lastPaymentDay.day, in: period) ? monthlyPlan : 0
}

/// Медиана трат категории за последние `monthCount` полных календарных месяцев до `day`; нет истории — 0.
public func calculateTypicalMonthlyAmount(categoryId: String, entries: [JournalEntry], before day: CalendarDay, monthCount: Int) -> Decimal {
    guard monthCount > 0 else { return 0 }
    let months = makeFullMonths(before: day, monthCount: monthCount)
    // Функцию зовут для обязательных и гибких категорий: для обоих видов покупка — плюс, возврат — минус.
    let kindsById: [String: CategoryKind] = [categoryId: .flexible]
    let monthlyAmounts = months.map { month in
        calculateCategorySpending(categoryId: categoryId, entries: findPeriodEntries(entries, period: month), kindsById: kindsById)
    }
    // Месяц без платежа — честный 0: закончившаяся рассрочка не должна держать план.
    return calculateMedian(monthlyAmounts)
}

/// Полные календарные месяцы, закончившиеся не позже `day`, от ближайшего к дальнему.
func makeFullMonths(before day: CalendarDay, monthCount: Int) -> [Period] {
    var months: [Period] = []
    var nextMonthStart = makeCalendarMonth(containing: day).start
    for _ in 0..<monthCount {
        let month = makeCalendarMonth(containing: nextMonthStart.adding(days: -1))
        months.append(month)
        nextMonthStart = month.start
    }
    return months
}

private func findLastPaymentDay(categoryId: String, entries: [JournalEntry], before day: CalendarDay) -> CalendarDay? {
    entries
        .filter { entry in entry.mergedInto == nil && entry.type == .expense && entry.categoryId == categoryId && entry.day < day }
        .map { entry in entry.day }
        .max()
}

/// Есть ли в периоде день с этим числом; платёж 31-го в коротком месяце приходится на последний день.
private func hasDayOfMonth(_ dayOfMonth: Int, in period: Period) -> Bool {
    period.days.contains { day in
        let isLastDayOfMonth = day.adding(days: 1).month != day.month
        return day.day == dayOfMonth || (isLastDayOfMonth && day.day < dayOfMonth)
    }
}

/// Траты гибких категорий, включая расходы без категории и комиссии банка.
func calculateFlexibleSpent(periodEntries: [JournalEntry], kindsById: [String: CategoryKind]) -> Decimal {
    calculateSpending(of: periodEntries, kinds: [.flexible], kindsById: kindsById)
}

/// Месячная сумма (лимит, цель) на период: в режиме «Полмесяца» — половина.
func calculateAmountForPeriod(monthlyAmount: Decimal, mode: PeriodMode) -> Decimal {
    mode == .halfMonth ? monthlyAmount / 2 : monthlyAmount
}

/// Сколько можно тратить в день: вниз до целого тенге, при перерасходе — 0.
func calculatePerDay(freeToSpend: Decimal, daysLeft: Int) -> Decimal {
    guard freeToSpend > 0 else { return 0 }
    return roundDownToWholeTenge(freeToSpend / Decimal(daysLeft))
}

/// Вниз до целого тенге: показанная сумма никогда не больше настоящей.
public func roundDownToWholeTenge(_ amount: Decimal) -> Decimal {
    var source = amount
    var rounded = Decimal()
    NSDecimalRound(&rounded, &source, 0, .down)
    return rounded
}

/// Вверх до целого тенге: перерасход не преуменьшаем.
public func roundUpToWholeTenge(_ amount: Decimal) -> Decimal {
    var source = amount
    var rounded = Decimal()
    NSDecimalRound(&rounded, &source, 0, .up)
    return rounded
}

// MARK: - Лимиты

/// Состояние лимитов категорий за период; категории без лимита не попадают. Самые потраченные — первыми.
public func calculateLimitStatuses(
    period: Period,
    today: CalendarDay,
    mode: PeriodMode,
    entries: [JournalEntry],
    categories: [SpendingCategory]
) -> [LimitStatus] {
    let kindsById = makeCategoryKindsById(categories)
    let periodEntries = findPeriodEntries(entries, period: period)
    let paceShare = calculatePaceShare(period: period, today: today)

    let statuses = categories.compactMap { category -> LimitStatus? in
        guard let monthlyLimit = category.monthlyLimit else { return nil }
        let limit = calculateAmountForPeriod(monthlyAmount: monthlyLimit, mode: mode)
        let spent = calculateCategorySpending(categoryId: category.id, entries: periodEntries, kindsById: kindsById)
        return LimitStatus(
            category: category,
            limit: limit,
            spent: spent,
            usedShare: calculateUsedShare(spent: spent, limit: limit),
            paceShare: paceShare,
            level: findLimitLevel(spent: spent, limit: limit, warnAtPercent: category.warnAtPercent)
        )
    }
    return statuses.sorted { first, second in first.usedShare > second.usedShare }
}

/// Доля прошедших дней периода, сегодня включительно, в пределах 0…1.
func calculatePaceShare(period: Period, today: CalendarDay) -> Double {
    let passedDays = period.start.daysUntil(today) + 1
    let share = Double(passedDays) / Double(period.dayCount)
    return min(max(share, 0), 1)
}

private func calculateUsedShare(spent: Decimal, limit: Decimal) -> Double {
    // Нулевой лимит: любая трата — бесконечный перерасход.
    guard limit > 0 else { return spent > 0 ? .infinity : 0 }
    return NSDecimalNumber(decimal: spent / limit).doubleValue
}

/// Уровень считается в Decimal, чтобы ровно 85 % не стали 84,999… из-за Double.
private func findLimitLevel(spent: Decimal, limit: Decimal, warnAtPercent: Int) -> LimitLevel {
    // Нулевой лимит означает «не тратить вовсе», поэтому любая трата — перерасход.
    guard limit > 0 else { return spent > 0 ? .over : .normal }
    guard spent <= limit else { return .over }
    guard spent * 100 < limit * Decimal(warnAtPercent) else { return .warning }
    return .normal
}
