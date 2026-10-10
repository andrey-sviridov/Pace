import Foundation

// Экран «Аналитика» (спека §8): листание периодов, линия плана, главные категории, продавцы, копилка по месяцам.
// Экран только раскладывает то, что посчитано здесь.

/// План трат к концу дня: весь и отдельно обязательные (ступеньками в дни платежей).
public struct DailyPlan: Equatable, Sendable {
    public let day: CalendarDay
    public let total: Decimal
    public let obligatoryTotal: Decimal
}

/// Строка диаграммы «Куда уходят деньги?»; `categoryId == nil` — «Прочее», сумма мелких категорий.
public struct CategorySpendingRow: Equatable, Sendable {
    public let categoryId: String?
    public let total: Decimal
}

/// Продавец в категории за период: название как в журнале, сумма и число операций.
public struct MerchantSpending: Equatable, Sendable {
    public let title: String
    public let total: Decimal
    public let operationCount: Int
}

// MARK: - Листание периодов

/// Период перед `period` в том же режиме.
public func makePreviousPeriod(before period: Period, mode: PeriodMode, salaryEvents: [SalaryEvent]) -> Period {
    makePeriod(containing: period.start.adding(days: -1), mode: mode, salaryEvents: salaryEvents)
}

/// Период после `period`; nil — он ещё не начался, в будущее не листаем.
public func makeNextPeriod(after period: Period, today: CalendarDay, mode: PeriodMode, salaryEvents: [SalaryEvent]) -> Period? {
    guard period.endExclusive <= today else { return nil }
    return makePeriod(containing: period.endExclusive, mode: mode, salaryEvents: salaryEvents)
}

/// Есть ли записи раньше `day`: листать назад, в периоды до первой выписки, незачем.
public func hasEntries(before day: CalendarDay, entries: [JournalEntry]) -> Bool {
    entries.contains { entry in entry.mergedInto == nil && entry.day < day }
}

/// Названия месяцев в именительном падеже — для заголовков («Сентябрь 2026»).
let nominativeMonthNames = ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь", "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"]

/// «Сентябрь», «Октябрь 2025»: месяц, на который приходится середина периода; год — только если не текущий.
public func formatPeriodTitle(_ period: Period, today: CalendarDay) -> String {
    let middleDay = findMiddleDay(of: period)
    let monthName = nominativeMonthNames[middleDay.month - 1]
    guard middleDay.year != today.year else { return monthName }
    return "\(monthName) \(middleDay.year)"
}

/// Середина периода: по ней период называется и по ней же находится при смене режима.
/// Зарплатный период 28 авг – 29 сен — это «сентябрь», хотя начинается в августе.
public func findMiddleDay(of period: Period) -> CalendarDay {
    period.start.adding(days: period.dayCount / 2)
}

/// «28 авг – 29 сен» для периода не с 1-го числа; у календарного месяца даты и так понятны — nil.
public func formatPeriodDates(_ period: Period) -> String? {
    guard period != makeCalendarMonth(containing: period.start) else { return nil }
    return "\(formatShortDay(period.start)) – \(formatShortDay(period.endExclusive.adding(days: -1)))"
}

// MARK: - Успеваю ли я?

/// План по дням периода: обязательные ступенькой в обычный день платежа, гибкие — ровно по дням.
/// Гибкие = сумма лимитов; лимитов нет — типичные гибкие траты (медиана за `flexibleLookbackMonthCount` месяцев).
public func makeSpendingPlan(
    period: Period,
    mode: PeriodMode,
    entries: [JournalEntry],
    categories: [SpendingCategory],
    flexibleLookbackMonthCount: Int
) -> [DailyPlan] {
    let obligatoryPayments = makeObligatoryPayments(period: period, mode: mode, entries: entries, categories: categories)
    let flexiblePlan = calculateFlexiblePlan(period: period, mode: mode, entries: entries, categories: categories, lookbackMonthCount: flexibleLookbackMonthCount)
    let dayCount = Decimal(period.dayCount)

    return period.days.enumerated().map { index, day in
        let obligatoryTotal = obligatoryPayments
            .filter { payment in payment.day <= day }
            .reduce(Decimal(0)) { total, payment in total + payment.amount }
        let flexibleTotal = flexiblePlan * Decimal(index + 1) / dayCount
        return DailyPlan(day: day, total: obligatoryTotal + flexibleTotal, obligatoryTotal: obligatoryTotal)
    }
}

/// Плановый платёж обязательной категории в периоде.
private struct PlannedPayment {
    let day: CalendarDay
    let amount: Decimal
}

/// Сумма — та же, что резервирует главная; день — число последнего платежа, без истории — первый день периода.
private func makeObligatoryPayments(period: Period, mode: PeriodMode, entries: [JournalEntry], categories: [SpendingCategory]) -> [PlannedPayment] {
    let obligatoryCategories = categories.filter { category in category.kind == .obligatory }
    return obligatoryCategories.map { category in
        let amount = calculatePlannedAmount(category: category, period: period, mode: mode, entries: entries)
        let lastPaymentDay = findLastPaymentDay(categoryId: category.id, entries: entries, before: period.start)
        let paymentDay = lastPaymentDay.flatMap { lastDay in findDay(withDayOfMonth: lastDay.day, in: period) } ?? period.start
        return PlannedPayment(day: paymentDay, amount: amount)
    }
}

/// Гибкие траты, которые план разрешает за период.
private func calculateFlexiblePlan(period: Period, mode: PeriodMode, entries: [JournalEntry], categories: [SpendingCategory], lookbackMonthCount: Int) -> Decimal {
    let monthlyLimits = categories
        .filter { category in category.kind == .flexible }
        .compactMap { category in category.monthlyLimit }
    guard monthlyLimits.isEmpty else {
        let limitsTotal = monthlyLimits.reduce(Decimal(0)) { total, limit in total + limit }
        return calculateAmountForPeriod(monthlyAmount: limitsTotal, mode: mode)
    }

    let kindsById = makeCategoryKindsById(categories)
    let monthlySpending = makeFullMonths(before: period.start, monthCount: lookbackMonthCount).map { month in
        calculateSpending(of: findPeriodEntries(entries, period: month), kinds: [.flexible], kindsById: kindsById)
    }
    guard !monthlySpending.isEmpty else { return 0 }
    return calculateAmountForPeriod(monthlyAmount: calculateMedian(monthlySpending), mode: mode)
}

/// «Потрачено 120k из плана 400k · сегодня день 12 из 30»; у прошедшего периода — «· период закончился».
public func makePaceCaption(spentTotal: Decimal, plannedTotal: Decimal, period: Period, today: CalendarDay) -> String {
    let spentText = "Потрачено \(formatThousands(spentTotal)) из плана \(formatThousands(plannedTotal))"
    guard period.contains(today) else { return "\(spentText) · период закончился" }
    let dayNumber = period.start.daysUntil(today) + 1
    return "\(spentText) · сегодня день \(dayNumber) из \(period.dayCount)"
}

/// Подпись выбранного пальцем дня: «12 окт: потрачено 120k · план 150k»; после сегодня трат ещё нет — только план.
public func makePaceSelectionText(plan: DailyPlan, spending: DailySpending?) -> String {
    let planText = "план \(formatThousands(plan.total))"
    guard let spending else { return "\(formatShortDay(plan.day)): \(planText)" }
    return "\(formatShortDay(plan.day)): потрачено \(formatThousands(spending.total)) · \(planText)"
}

// MARK: - Куда уходят деньги?

/// Не больше `maxRowCount` строк: если категорий больше, последние сливаются в «Прочее».
/// Одна-единственная «лишняя» категория показывается своим именем — «Прочее» из одной строки только прячет название.
public func makeTopCategoryRows(_ spending: [CategorySpending], maxRowCount: Int) -> [CategorySpendingRow] {
    let allRows = spending.map { item in CategorySpendingRow(categoryId: item.categoryId, total: item.total) }
    guard allRows.count > maxRowCount else { return allRows }

    let shownRows = allRows.prefix(maxRowCount - 1)
    let otherTotal = allRows.dropFirst(maxRowCount - 1).reduce(Decimal(0)) { total, row in total + row.total }
    return Array(shownRows) + [CategorySpendingRow(categoryId: nil, total: otherTotal)]
}

/// Продавцы категории за период, от больших сумм к меньшим. Считаются те же части трат, что и в строке категории,
/// поэтому сумма продавцов равна полосе (комиссии банка — по операциям, с которых их сняли; возвраты — минусом).
public func calculateMerchantSpending(categoryId: String, period: Period, entries: [JournalEntry], categories: [SpendingCategory]) -> [MerchantSpending] {
    let kindsById = makeCategoryKindsById(categories)
    var totalsByTitle: [String: Decimal] = [:]
    var countsByTitle: [String: Int] = [:]
    for entry in findPeriodEntries(entries, period: period) {
        let categoryParts = makeSpendingParts(of: entry, kindsById: kindsById).filter { part in part.categoryId == categoryId && part.amount != 0 }
        for part in categoryParts {
            totalsByTitle[entry.title, default: 0] += part.amount
            countsByTitle[entry.title, default: 0] += 1
        }
    }

    let merchants = totalsByTitle.map { title, total in
        MerchantSpending(title: title, total: total, operationCount: countsByTitle[title] ?? 0)
    }
    // При равных суммах — по алфавиту, иначе строки прыгали бы между открытиями.
    return merchants.sorted { first, second in
        first.total == second.total ? first.title < second.title : first.total > second.total
    }
}

// MARK: - Получается ли копить?

/// `count` периодов, последний — тот, где лежит `period`, от старого к новому.
/// В режиме «Полмесяца» — зарплатные месяцы: половинки с авансом и с зарплатой несравнимы, а подпись говорит «в месяц».
public func makeLeftoverPeriods(endingWith period: Period, mode: PeriodMode, salaryEvents: [SalaryEvent], count: Int) -> [Period] {
    guard count > 0 else { return [] }
    let historyMode: PeriodMode = mode == .halfMonth ? .salaryMonth : mode
    var periods = [makePeriod(containing: period.start, mode: historyMode, salaryEvents: salaryEvents)]
    while periods.count < count {
        periods.insert(makePreviousPeriod(before: periods[0], mode: historyMode, salaryEvents: salaryEvents), at: 0)
    }
    return periods
}

/// Среднее «осталось» только по закончившимся периодам: идущий ещё без зарплаты и занизил бы среднее. Таких нет — nil.
public func calculateAverageLeftover(_ leftovers: [PeriodLeftover], today: CalendarDay) -> Decimal? {
    let finishedLeftovers = leftovers.filter { item in item.period.endExclusive <= today }
    guard !finishedLeftovers.isEmpty else { return nil }
    let total = finishedLeftovers.reduce(Decimal(0)) { sum, item in sum + item.leftover }
    return total / Decimal(finishedLeftovers.count)
}

/// «В среднем откладывается 120k в месяц» или «В среднем тратится на 40k больше дохода в месяц».
public func makeLeftoverCaption(averageLeftover: Decimal) -> String {
    guard averageLeftover < 0 else { return "В среднем откладывается \(formatThousands(averageLeftover)) в месяц" }
    return "В среднем тратится на \(formatThousands(-averageLeftover)) больше дохода в месяц"
}

/// «+347k», «−360k», «0»: знак виден, даже когда цвет не различить.
public func formatSignedThousands(_ amount: Decimal) -> String {
    let text = formatThousands(abs(amount))
    guard text != "0" else { return text }
    return amount < 0 ? "−\(text)" : "+\(text)"
}
