import Foundation
import Testing
@testable import KopilkaCore

@Suite struct AnalyticsScreenDataTests {
    // MARK: - Листание периодов

    @Test func stepsBackAndForwardBetweenCalendarMonths() {
        let october = makeOctober2026()

        let september = makePreviousPeriod(before: october, mode: .calendarMonth, salaryEvents: [])

        #expect(september == Period(start: makeDay("01.09.2026"), endExclusive: makeDay("01.10.2026")))
        #expect(makeNextPeriod(after: september, today: makeDay("10.10.2026"), mode: .calendarMonth, salaryEvents: []) == october)
    }

    @Test func doesNotStepIntoFuture() {
        let today = makeDay("10.10.2026")
        #expect(makeNextPeriod(after: makeOctober2026(), today: today, mode: .calendarMonth, salaryEvents: []) == nil)
    }

    @Test func stepsBetweenSalaryPeriods() {
        let events = [makeSalaryEvent("28.08.2026", .salary), makeSalaryEvent("30.09.2026", .salary)]
        let current = makePeriod(containing: makeDay("10.10.2026"), mode: .salaryMonth, salaryEvents: events)

        let previous = makePreviousPeriod(before: current, mode: .salaryMonth, salaryEvents: events)

        #expect(previous == Period(start: makeDay("28.08.2026"), endExclusive: makeDay("30.09.2026")))
        #expect(makeNextPeriod(after: previous, today: makeDay("10.10.2026"), mode: .salaryMonth, salaryEvents: events) == current)
        #expect(makeNextPeriod(after: current, today: makeDay("10.10.2026"), mode: .salaryMonth, salaryEvents: events) == nil)
    }

    @Test func stepsBackOnlyWhileThereAreEarlierEntries() {
        let entries = [makeBudgetEntry("20.08.2026", .expense, 1_000, categoryId: "groceries")]

        #expect(hasEntries(before: makeDay("01.09.2026"), entries: entries))
        #expect(!hasEntries(before: makeDay("01.08.2026"), entries: entries))
    }

    @Test func middleDayKeepsMonthWhenModeChanges() {
        let salaryPeriod = Period(start: makeDay("28.08.2026"), endExclusive: makeDay("30.09.2026"))

        let middleDay = findMiddleDay(of: salaryPeriod)

        #expect(makePeriod(containing: middleDay, mode: .calendarMonth, salaryEvents: []).start == makeDay("01.09.2026"))
    }

    @Test func periodTitleUsesMiddleMonthAndYearOnlyWhenNotCurrent() {
        let salaryPeriod = Period(start: makeDay("28.08.2026"), endExclusive: makeDay("30.09.2026"))
        let oldOctober = Period(start: makeDay("01.10.2025"), endExclusive: makeDay("01.11.2025"))

        #expect(formatPeriodTitle(salaryPeriod, today: makeDay("10.10.2026")) == "Сентябрь")
        #expect(formatPeriodTitle(oldOctober, today: makeDay("10.10.2026")) == "Октябрь 2025")
        #expect(formatPeriodDates(salaryPeriod) == "28 авг – 29 сен")
        #expect(formatPeriodDates(makeOctober2026()) == nil)
    }

    // MARK: - План

    @Test func planPutsObligatoryOnUsualPaymentDayAndSpreadsLimits() {
        let categories = makeBuiltInCategories()
        setMonthlyLimit(31_000, categoryId: "groceries", in: categories)
        // Ипотека 15-го три месяца подряд: план 100 000 ступенькой 15 октября.
        let entries = [
            makeBudgetEntry("15.07.2026", .expense, 100_000, categoryId: "mortgage"),
            makeBudgetEntry("15.08.2026", .expense, 100_000, categoryId: "mortgage"),
            makeBudgetEntry("15.09.2026", .expense, 100_000, categoryId: "mortgage"),
        ]

        let plan = makeSpendingPlan(period: makeOctober2026(), mode: .calendarMonth, entries: entries, categories: categories, flexibleLookbackMonthCount: 6)

        #expect(plan.count == 31)
        #expect(plan[13].obligatoryTotal == 0)
        #expect(plan[14].obligatoryTotal == 100_000)
        #expect(plan[0].total == 1_000)
        #expect(plan[14].total == 115_000)
        #expect(plan.last?.total == 131_000)
    }

    @Test func planWithoutLimitsUsesTypicalFlexibleSpending() {
        let categories = makeBuiltInCategories()
        let entries = [
            makeBudgetEntry("05.08.2026", .expense, 62_000, categoryId: "cafes"),
            makeBudgetEntry("05.09.2026", .expense, 62_000, categoryId: "groceries"),
            makeBudgetEntry("06.09.2026", .expense, 300, categoryId: "transport"),
        ]

        let plan = makeSpendingPlan(period: makeOctober2026(), mode: .calendarMonth, entries: entries, categories: categories, flexibleLookbackMonthCount: 2)

        // Медиана августа (62 000) и сентября (62 300).
        #expect(plan.last?.total == 62_150)
        #expect(plan.last?.obligatoryTotal == 0)
    }

    @Test func halfMonthPlanHalvesLimits() {
        let categories = makeBuiltInCategories()
        setMonthlyLimit(40_000, categoryId: "groceries", in: categories)
        let half = Period(start: makeDay("15.10.2026"), endExclusive: makeDay("30.10.2026"))

        let plan = makeSpendingPlan(period: half, mode: .halfMonth, entries: [], categories: categories, flexibleLookbackMonthCount: 6)

        #expect(plan.last?.total == 20_000)
    }

    @Test func paceCaptionNamesTodayOrFinishedPeriod() {
        let october = makeOctober2026()

        #expect(makePaceCaption(spentTotal: 120_000, plannedTotal: 400_000, period: october, today: makeDay("12.10.2026"))
            == "Потрачено 120k из плана 400k · сегодня день 12 из 31")
        #expect(makePaceCaption(spentTotal: 380_000, plannedTotal: 400_000, period: october, today: makeDay("02.11.2026"))
            == "Потрачено 380k из плана 400k · период закончился")
    }

    @Test func selectionTextShowsSpentOnlyUpToToday() {
        let plan = DailyPlan(day: makeDay("12.10.2026"), total: 150_000, obligatoryTotal: 100_000)
        let spending = DailySpending(day: makeDay("12.10.2026"), total: 120_000, obligatoryTotal: 100_000)

        #expect(makePaceSelectionText(plan: plan, spending: spending) == "12 окт: потрачено 120k · план 150k")
        #expect(makePaceSelectionText(plan: plan, spending: nil) == "12 окт: план 150k")
    }

    // MARK: - Категории и продавцы

    @Test func extraCategoriesFoldIntoOther() {
        let spending = (1...11).map { index in CategorySpending(categoryId: "c\(index)", total: Decimal(100 - index)) }

        let rows = makeTopCategoryRows(spending, maxRowCount: 9)

        #expect(rows.count == 9)
        #expect(rows.prefix(8).map { row in row.categoryId } == (1...8).map { index in "c\(index)" })
        #expect(rows.last == CategorySpendingRow(categoryId: nil, total: 91 + 90 + 89))
    }

    @Test func singleExtraCategoryKeepsItsName() {
        let spending = (1...9).map { index in CategorySpending(categoryId: "c\(index)", total: Decimal(100 - index)) }

        let rows = makeTopCategoryRows(spending, maxRowCount: 9)

        #expect(rows.map { row in row.categoryId } == (1...9).map { index in "c\(index)" })
    }

    @Test func merchantsSumUpToCategoryBar() {
        let categories = makeBuiltInCategories()
        let entries = [
            makeTitledEntry("01.10.2026", .expense, 3_000, title: "Magnum", categoryId: "groceries"),
            makeTitledEntry("05.10.2026", .expense, 2_000, title: "Magnum", categoryId: "groceries"),
            makeTitledEntry("06.10.2026", .income, 500, title: "Magnum", categoryId: "groceries"),
            makeTitledEntry("07.10.2026", .expense, 4_000, title: "Small", categoryId: "groceries", feeTenge: 100),
            makeTitledEntry("08.10.2026", .expense, 9_000, title: "Кофейня", categoryId: "cafes"),
            makeTitledEntry("30.09.2026", .expense, 7_000, title: "Magnum", categoryId: "groceries"),
        ]

        let merchants = calculateMerchantSpending(categoryId: "groceries", period: makeOctober2026(), entries: entries, categories: categories)
        let bar = calculateSpendingByCategory(period: makeOctober2026(), entries: entries, categories: categories)
            .first { item in item.categoryId == "groceries" }

        #expect(merchants == [
            MerchantSpending(title: "Magnum", total: 4_500, operationCount: 3),
            MerchantSpending(title: "Small", total: 4_000, operationCount: 1),
        ])
        #expect(merchants.reduce(Decimal(0)) { total, merchant in total + merchant.total } == bar?.total)
    }

    @Test func bankFeesListOperationsTheyWereChargedOn() {
        let categories = makeBuiltInCategories()
        let entries = [
            makeTitledEntry("01.10.2026", .transfer, 30_000, title: "Перевод на Kaspi", categoryId: "ownTransfer", feeTenge: 250),
        ]

        let merchants = calculateMerchantSpending(categoryId: "bankFees", period: makeOctober2026(), entries: entries, categories: categories)

        #expect(merchants == [MerchantSpending(title: "Перевод на Kaspi", total: 250, operationCount: 1)])
    }

    // MARK: - Копилка по месяцам

    @Test func leftoverPeriodsEndWithSelectedPeriod() {
        let periods = makeLeftoverPeriods(endingWith: makeOctober2026(), mode: .calendarMonth, salaryEvents: [], count: 6)

        #expect(periods.count == 6)
        #expect(periods.first?.start == makeDay("01.05.2026"))
        #expect(periods.last == makeOctober2026())
    }

    @Test func halfMonthLeftoverUsesSalaryMonths() {
        let events = [
            makeSalaryEvent("28.08.2026", .salary),
            makeSalaryEvent("15.09.2026", .advance, 200_000),
            makeSalaryEvent("30.09.2026", .salary),
        ]
        let half = Period(start: makeDay("15.09.2026"), endExclusive: makeDay("30.09.2026"))

        let periods = makeLeftoverPeriods(endingWith: half, mode: .halfMonth, salaryEvents: events, count: 2)

        #expect(periods.last == Period(start: makeDay("28.08.2026"), endExclusive: makeDay("30.09.2026")))
        #expect(periods.first?.endExclusive == makeDay("28.08.2026"))
    }

    @Test func averageLeftoverSkipsUnfinishedPeriod() {
        let leftovers = [
            PeriodLeftover(period: Period(start: makeDay("01.08.2026"), endExclusive: makeDay("01.09.2026")), leftover: 100_000),
            PeriodLeftover(period: Period(start: makeDay("01.09.2026"), endExclusive: makeDay("01.10.2026")), leftover: -40_000),
            PeriodLeftover(period: makeOctober2026(), leftover: -300_000),
        ]

        #expect(calculateAverageLeftover(leftovers, today: makeDay("10.10.2026")) == 30_000)
        #expect(calculateAverageLeftover(Array(leftovers.suffix(1)), today: makeDay("10.10.2026")) == nil)
    }

    @Test func leftoverTextsShowSign() {
        #expect(formatSignedThousands(347_000) == "+347k")
        #expect(formatSignedThousands(-360_400) == "−360k")
        #expect(formatSignedThousands(0) == "0")
        #expect(makeLeftoverCaption(averageLeftover: 120_000) == "В среднем откладывается 120k в месяц")
        #expect(makeLeftoverCaption(averageLeftover: -40_000) == "В среднем тратится на 40k больше дохода в месяц")
    }
}

private func setMonthlyLimit(_ limitTenge: Decimal, categoryId: String, in categories: [SpendingCategory]) {
    guard let category = categories.first(where: { category in category.id == categoryId }) else {
        preconditionFailure("Нет категории \(categoryId)")
    }
    category.monthlyLimit = limitTenge
}

private func makeTitledEntry(
    _ dotted: String,
    _ type: EntryType,
    _ amountTenge: Decimal,
    title: String,
    categoryId: String?,
    feeTenge: Decimal = 0
) -> JournalEntry {
    let entry = makeBudgetEntry(dotted, type, amountTenge, categoryId: categoryId, feeTenge: feeTenge)
    entry.title = title
    return entry
}
