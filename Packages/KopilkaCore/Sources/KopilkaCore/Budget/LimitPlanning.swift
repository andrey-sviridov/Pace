import Foundation

// Экран «Лимиты на месяц» и карточка категории (спека §5.8, §8): план дохода, средние, подсказки лимита.

/// Строка категории на экране лимитов.
public struct CategoryLimitRow {
    public let category: SpendingCategory
    /// Медиана трат в месяц — «в среднем Nk».
    public let averageMonthly: Decimal
    /// Обязательная — ожидаемая сумма (заданная вручную или средняя); гибкая — лимит или nil «без лимита».
    public let plannedMonthly: Decimal?
}

/// План месяца: доход → обязательные → цель → сумма лимитов → не распределено.
public struct LimitPlan: Equatable, Sendable {
    public let income: Decimal
    public let obligatoryTotal: Decimal
    public let savingsGoal: Decimal
    public let limitsTotal: Decimal
    /// Доход минус всё распределённое; минус — распределено больше, чем приходит.
    public let unallocated: Decimal
}

/// Сколько сэкономит лимит ниже обычных трат.
public struct LimitSavings: Equatable, Sendable {
    public let perMonth: Decimal
    public let perYear: Decimal
}

// MARK: - Экран лимитов

/// Типичный доход в месяц: медиана фактического дохода за `monthCount` полных календарных месяцев до `day`.
/// Доход считается по тем же правилам, что и в бюджете (категории дохода и поступления без категории;
/// без процентов и поступлений на депозит). Нет истории — 0.
public func calculateTypicalMonthlyIncome(entries: [JournalEntry], categories: [SpendingCategory], before day: CalendarDay, monthCount: Int) -> Decimal {
    guard monthCount > 0 else { return 0 }
    let kindsById = makeCategoryKindsById(categories)
    let monthlyIncomes = makeFullMonths(before: day, monthCount: monthCount).map { month in
        calculateActualIncome(of: findPeriodEntries(entries, period: month), kindsById: kindsById)
    }
    return calculateMedian(monthlyIncomes)
}

/// Строки категорий одного вида с их средним за `monthCount` месяцев.
/// Гибкие — от самых больших трат: резать имеет смысл прежде всего их. Обязательные — в порядке категорий.
public func makeLimitRows(
    categories: [SpendingCategory],
    kind: CategoryKind,
    entries: [JournalEntry],
    before day: CalendarDay,
    monthCount: Int
) -> [CategoryLimitRow] {
    let kindCategories = categories
        .filter { category in category.kind == kind }
        .sorted { first, second in first.sortOrder < second.sortOrder }
    let rows = kindCategories.map { category in
        let average = calculateTypicalMonthlyAmount(categoryId: category.id, entries: entries, before: day, monthCount: monthCount)
        let planned = kind == .obligatory ? (category.expectedMonthlyAmount ?? average) : category.monthlyLimit
        return CategoryLimitRow(category: category, averageMonthly: average, plannedMonthly: planned)
    }
    guard kind == .flexible else { return rows }
    return rows.sorted { first, second in first.averageMonthly > second.averageMonthly }
}

/// План из строк экрана: обязательные — ожидаемые суммы, лимиты — только у гибких, где лимит задан.
public func calculateLimitPlan(
    monthlyIncome: Decimal,
    obligatoryRows: [CategoryLimitRow],
    flexibleRows: [CategoryLimitRow],
    monthlySavingsGoal: Decimal
) -> LimitPlan {
    let obligatoryTotal = obligatoryRows.reduce(Decimal(0)) { total, row in total + (row.plannedMonthly ?? 0) }
    let limitsTotal = flexibleRows.reduce(Decimal(0)) { total, row in total + (row.plannedMonthly ?? 0) }
    return LimitPlan(
        income: monthlyIncome,
        obligatoryTotal: obligatoryTotal,
        savingsGoal: monthlySavingsGoal,
        limitsTotal: limitsTotal,
        unallocated: monthlyIncome - obligatoryTotal - monthlySavingsGoal - limitsTotal
    )
}

// MARK: - Карточка категории

/// Прошедшие периоды для столбиков карточки, от старого к новому; текущий незаконченный не входит.
public func makeLimitHistoryPeriods(today: CalendarDay, mode: PeriodMode, salaryEvents: [SalaryEvent], count: Int) -> [Period] {
    // Лимит задаётся на месяц: в режиме «Полмесяца» столбики-половинки нельзя сравнить с месячной линией лимита.
    let historyMode: PeriodMode = mode == .halfMonth ? .salaryMonth : mode
    var periods: [Period] = []
    var nextStart = makePeriod(containing: today, mode: historyMode, salaryEvents: salaryEvents).start
    for _ in 0..<count {
        let period = makePeriod(containing: nextStart.adding(days: -1), mode: historyMode, salaryEvents: salaryEvents)
        periods.append(period)
        nextStart = period.start
    }
    return periods.reversed()
}

/// Самые крупные продавцы категории за период — по сумме покупок, названия как в журнале.
public func findTopMerchantTitles(categoryId: String, entries: [JournalEntry], period: Period, count: Int) -> [String] {
    let purchases = findPeriodEntries(entries, period: period).filter { entry in
        entry.type == .expense && (entry.categoryId ?? "uncategorized") == categoryId
    }
    var totalsByTitle: [String: Decimal] = [:]
    for purchase in purchases {
        totalsByTitle[purchase.title, default: 0] += purchase.amount
    }
    let sortedTitles = totalsByTitle.sorted { first, second in
        // При равных суммах — по алфавиту, иначе подпись прыгала бы между открытиями.
        first.value == second.value ? first.key < second.key : first.value > second.value
    }
    return sortedTitles.prefix(count).map { title, total in title }
}

/// Подсказка лимита: среднее, урезанное на `cutPercent` процентов и округлённое до шага ползунка.
public func makeSuggestedLimit(averageMonthly: Decimal, cutPercent: Int, roundingStepTenge: Decimal) -> Decimal {
    let cutAmount = averageMonthly * Decimal(100 - cutPercent) / 100
    return roundToStep(cutAmount, stepTenge: roundingStepTenge)
}

/// Правый край ползунка: двойное среднее, но не меньше `minimumTenge` и не меньше текущего лимита.
public func calculateLimitSliderMaximum(averageMonthly: Decimal, currentLimit: Decimal?, minimumTenge: Decimal, stepTenge: Decimal) -> Decimal {
    let maximum = max(averageMonthly * 2, minimumTenge, currentLimit ?? 0)
    return roundUpToStep(maximum, stepTenge: stepTenge)
}

/// Экономия = (среднее − лимит) в месяц, вниз до тенге, и ×12 в год; лимит не ниже обычных трат ничего не экономит — nil.
public func calculateLimitSavings(averageMonthly: Decimal, monthlyLimit: Decimal) -> LimitSavings? {
    guard monthlyLimit < averageMonthly else { return nil }
    // Среднее — медиана с копейками; экономию обещаем вниз до целого тенге, не больше настоящей.
    let perMonth = roundDownToWholeTenge(averageMonthly - monthlyLimit)
    return LimitSavings(perMonth: perMonth, perYear: perMonth * 12)
}

/// Ближайшее кратное шагу.
func roundToStep(_ amount: Decimal, stepTenge: Decimal) -> Decimal {
    var steps = amount / stepTenge
    var roundedSteps = Decimal()
    NSDecimalRound(&roundedSteps, &steps, 0, .plain)
    return roundedSteps * stepTenge
}

private func roundUpToStep(_ amount: Decimal, stepTenge: Decimal) -> Decimal {
    var steps = amount / stepTenge
    var roundedSteps = Decimal()
    NSDecimalRound(&roundedSteps, &steps, 0, .up)
    return roundedSteps * stepTenge
}
