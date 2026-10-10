import Foundation

/// Всё, что показывает главная (спека §8), посчитанное за один проход по записям.
public struct HomeNumbers {
    public let period: Period
    public let budget: BudgetSummary
    /// Какое поступление закрывает период; nil — период кончается вместе с месяцем.
    public let periodEndKind: SalaryEventKind?
    /// Самые потраченные — первыми.
    public let limitStatuses: [LimitStatus]
    public let cardBalance: Decimal
    public let depositBalance: Decimal
    public let unreviewedCount: Int
}

/// Поступления зарплаты считает вызывающий: пороги аванса и разовой премии видны в месте вызова.
public func calculateHomeNumbers(
    today: CalendarDay,
    mode: PeriodMode,
    monthlySavingsGoal: Decimal,
    entries: [JournalEntry],
    categories: [SpendingCategory],
    accounts: [Account],
    salaryEvents: [SalaryEvent]
) -> HomeNumbers {
    let period = makePeriod(containing: today, mode: mode, salaryEvents: salaryEvents)
    let budget = calculateBudget(
        period: period,
        today: today,
        mode: mode,
        entries: entries,
        categories: categories,
        salaryEvents: salaryEvents,
        monthlySavingsGoal: monthlySavingsGoal
    )
    let cardAccounts = accounts.filter { account in account.kind == .card }
    let depositAccounts = accounts.filter { account in account.kind == .deposit }

    return HomeNumbers(
        period: period,
        budget: budget,
        periodEndKind: findPeriodEndKind(period: period, mode: mode, salaryEvents: salaryEvents),
        limitStatuses: calculateLimitStatuses(period: period, today: today, mode: mode, entries: entries, categories: categories),
        cardBalance: calculateTotalBalance(of: cardAccounts, entries: entries),
        depositBalance: calculateTotalBalance(of: depositAccounts, entries: entries),
        unreviewedCount: entries.filter { entry in isAwaitingReview(entry) }.count
    )
}

private func calculateTotalBalance(of accounts: [Account], entries: [JournalEntry]) -> Decimal {
    accounts.reduce(Decimal(0)) { total, account in total + calculateBalance(account: account, entries: entries) }
}

// MARK: - Подписи главной

/// «Можно потратить до зарплаты» или при перерасходе «Перерасход до зарплаты».
public func makeHeroTitle(numbers: HomeNumbers) -> String {
    let endLabel = makePeriodEndLabel(periodEndKind: numbers.periodEndKind)
    let isOverspent = numbers.budget.freeToSpend < 0
    return isOverspent ? "Перерасход \(endLabel)" : "Можно потратить \(endLabel)"
}

/// «до зарплаты» / «до аванса» / «до конца месяца».
public func makePeriodEndLabel(periodEndKind: SalaryEventKind?) -> String {
    guard let periodEndKind else { return "до конца месяца" }
    switch periodEndKind {
    case .salary:
        return "до зарплаты"
    case .advance:
        return "до аванса"
    }
}

/// Главная цифра без копеек: свободные — вниз (не обещаем лишнего), перерасход — вверх и без минуса (не преуменьшаем).
public func makeHeroAmount(freeToSpend: Decimal) -> Decimal {
    guard freeToSpend < 0 else { return roundDownToWholeTenge(freeToSpend) }
    return roundUpToWholeTenge(-freeToSpend)
}

/// «зарплата ~15 окт · 6 дней · ≈31 000 ₸ в день»; при перерасходе без «в день».
public func makeHeroCaption(numbers: HomeNumbers) -> String {
    let endText = makePeriodEndText(period: numbers.period, periodEndKind: numbers.periodEndKind)
    let daysText = formatDayCount(numbers.budget.daysLeft)
    guard numbers.budget.freeToSpend >= 0 else { return [endText, daysText].joined(separator: " · ") }
    return [endText, daysText, "≈\(formatTenge(numbers.budget.perDay)) в день"].joined(separator: " · ")
}

/// Поступление ожидается в день конца периода, поэтому с «~»; у календарного месяца — его последний день.
private func makePeriodEndText(period: Period, periodEndKind: SalaryEventKind?) -> String {
    switch periodEndKind {
    case .salary:
        return "зарплата ~\(formatShortDay(period.endExclusive))"
    case .advance:
        return "аванс ~\(formatShortDay(period.endExclusive))"
    case nil:
        return "по \(formatShortDay(period.endExclusive.adding(days: -1)))"
    }
}
