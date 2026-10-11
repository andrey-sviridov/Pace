import Foundation
import Testing
@testable import PaceCore

@Suite struct LimitPlanningTests {
    // MARK: - Доход

    @Test func typicalIncomeIsMedianOfFullMonths() {
        let categories = makeBuiltInCategories()
        let deposit = Account(kind: .deposit, title: "Депозит", number: "KZ1", anchorBalance: 0, anchorDay: makeDay("01.01.2026"))
        let entries = [
            makeBudgetEntry("10.07.2026", .income, 300_000, categoryId: "salary"),
            makeBudgetEntry("10.08.2026", .income, 800_000, categoryId: "salary"),
            makeBudgetEntry("12.08.2026", .income, 5_000, categoryId: "refunds"),
            makeBudgetEntry("10.09.2026", .income, 700_000, categoryId: "salary"),
            makeBudgetEntry("11.09.2026", .income, 20_000, categoryId: nil),
            // Не доход: проценты, поступление на депозит, возврат в категорию трат, текущий месяц.
            makeBudgetEntry("15.09.2026", .income, 9_000, categoryId: "depositInterest"),
            makeBudgetEntry("16.09.2026", .income, 50_000, categoryId: "incomingTransfers", account: deposit),
            makeBudgetEntry("17.09.2026", .income, 3_000, categoryId: "groceries"),
            makeBudgetEntry("05.10.2026", .income, 900_000, categoryId: "salary"),
        ]

        let income = calculateTypicalMonthlyIncome(entries: entries, categories: categories, before: makeDay("09.10.2026"), monthCount: 3)

        // Июль 300 000, август 805 000, сентябрь 720 000 → медиана 720 000.
        #expect(income == 720_000)
    }

    @Test func typicalIncomeWithoutHistoryIsZero() {
        let income = calculateTypicalMonthlyIncome(entries: [], categories: makeBuiltInCategories(), before: makeDay("09.10.2026"), monthCount: 3)
        #expect(income == 0)
    }

    // MARK: - Строки и план

    @Test func obligatoryRowsUseManualAmountOrAverage() {
        let categories = makeBuiltInCategories()
        let mortgage = findCategory("mortgage", in: categories)
        mortgage.expectedMonthlyAmount = 150_000
        let entries = [
            makeBudgetEntry("05.07.2026", .expense, 20_000, categoryId: "utilities"),
            makeBudgetEntry("05.08.2026", .expense, 24_000, categoryId: "utilities"),
            makeBudgetEntry("05.09.2026", .expense, 22_000, categoryId: "utilities"),
            makeBudgetEntry("05.09.2026", .expense, 140_000, categoryId: "mortgage"),
        ]

        let rows = makeLimitRows(categories: categories, kind: .obligatory, entries: entries, before: makeDay("09.10.2026"), monthCount: 3)

        #expect(rows.map { row in row.category.id } == ["mortgage", "loans", "installments", "family", "utilities"])
        let mortgageRow = rows[0]
        let utilitiesRow = rows[4]
        #expect(mortgageRow.averageMonthly == 0)
        #expect(mortgageRow.plannedMonthly == 150_000)
        #expect(utilitiesRow.averageMonthly == 22_000)
        #expect(utilitiesRow.plannedMonthly == 22_000)
    }

    @Test func flexibleRowsAreSortedByAverageAndShowLimit() {
        let categories = makeBuiltInCategories()
        findCategory("cafes", in: categories).monthlyLimit = 30_000
        let entries = [
            makeBudgetEntry("05.09.2026", .expense, 10_000, categoryId: "groceries"),
            makeBudgetEntry("05.09.2026", .expense, 40_000, categoryId: "cafes"),
            makeBudgetEntry("05.08.2026", .expense, 40_000, categoryId: "cafes"),
            makeBudgetEntry("05.08.2026", .expense, 10_000, categoryId: "groceries"),
        ]

        let rows = makeLimitRows(categories: categories, kind: .flexible, entries: entries, before: makeDay("09.10.2026"), monthCount: 2)

        #expect(rows.prefix(2).map { row in row.category.id } == ["cafes", "groceries"])
        #expect(rows[0].averageMonthly == 40_000)
        #expect(rows[0].plannedMonthly == 30_000)
        #expect(rows[1].plannedMonthly == nil)
        #expect(rows.allSatisfy { row in row.category.kind == .flexible })
    }

    @Test func planShowsUnallocatedAndOverAllocation() {
        let categories = makeBuiltInCategories()
        let obligatoryRows = [CategoryLimitRow(category: categories[0], averageMonthly: 0, plannedMonthly: 300_000)]
        let flexibleRows = [
            CategoryLimitRow(category: categories[5], averageMonthly: 0, plannedMonthly: 100_000),
            CategoryLimitRow(category: categories[6], averageMonthly: 0, plannedMonthly: nil),
            CategoryLimitRow(category: categories[7], averageMonthly: 0, plannedMonthly: 50_000),
        ]

        let plan = calculateLimitPlan(monthlyIncome: 805_000, obligatoryRows: obligatoryRows, flexibleRows: flexibleRows, monthlySavingsGoal: 100_000)
        let overPlan = calculateLimitPlan(monthlyIncome: 400_000, obligatoryRows: obligatoryRows, flexibleRows: flexibleRows, monthlySavingsGoal: 100_000)

        #expect(plan == LimitPlan(income: 805_000, obligatoryTotal: 300_000, savingsGoal: 100_000, limitsTotal: 150_000, unallocated: 255_000))
        #expect(overPlan.unallocated == -150_000)
    }

    // MARK: - Карточка категории

    @Test func historyPeriodsAreFullMonthsBeforeCurrent() {
        let periods = makeLimitHistoryPeriods(today: makeDay("09.10.2026"), mode: .calendarMonth, salaryEvents: [], count: 3)

        #expect(periods.map { period in period.start } == [makeDay("01.07.2026"), makeDay("01.08.2026"), makeDay("01.09.2026")])
        #expect(periods.last?.endExclusive == makeDay("01.10.2026"))
    }

    @Test func halfMonthHistoryUsesSalaryMonths() {
        let salaryEvents = [
            makeSalaryEvent("10.08.2026", .salary),
            makeSalaryEvent("25.08.2026", .advance, 200_000),
            makeSalaryEvent("10.09.2026", .salary),
            makeSalaryEvent("25.09.2026", .advance, 200_000),
            makeSalaryEvent("09.10.2026", .salary),
        ]

        let periods = makeLimitHistoryPeriods(today: makeDay("12.10.2026"), mode: .halfMonth, salaryEvents: salaryEvents, count: 2)

        #expect(periods == [
            Period(start: makeDay("10.08.2026"), endExclusive: makeDay("10.09.2026")),
            Period(start: makeDay("10.09.2026"), endExclusive: makeDay("09.10.2026")),
        ])
    }

    @Test func topMerchantsAreSortedBySpending() {
        let entries = [
            makeTitledEntry("Magnum", 5_000),
            makeTitledEntry("Small", 6_000),
            makeTitledEntry("Magnum", 4_000),
            makeTitledEntry("Arbuz", 7_000),
            makeTitledEntry("Galmart", 1_000),
            makeTitledEntry("Anvar", 1_000),
        ]

        let titles = findTopMerchantTitles(categoryId: "groceries", entries: entries, period: makeOctober2026(), count: 4)

        #expect(titles == ["Magnum", "Arbuz", "Small", "Anvar"])
    }

    @Test func suggestedLimitsRoundToSliderStep() {
        #expect(makeSuggestedLimit(averageMonthly: 56_200, cutPercent: 0, roundingStepTenge: 1_000) == 56_000)
        #expect(makeSuggestedLimit(averageMonthly: 56_000, cutPercent: 20, roundingStepTenge: 1_000) == 45_000)
        #expect(makeSuggestedLimit(averageMonthly: 56_000, cutPercent: 40, roundingStepTenge: 1_000) == 34_000)
        #expect(makeSuggestedLimit(averageMonthly: 300, cutPercent: 0, roundingStepTenge: 1_000) == 1_000)
        #expect(makeSuggestedLimit(averageMonthly: 0, cutPercent: 40, roundingStepTenge: 1_000) == 1_000)
    }

    @Test func medianAmountMatchesShownBars() {
        #expect(calculateMedianAmount([10_000, 90_000, 30_000]) == 30_000)
        #expect(calculateMedianAmount([10_000, 20_000, 30_000, 90_000]) == 25_000)
        #expect(calculateMedianAmount([]) == 0)
    }

    @Test func obligatoryRowMatchesHomePlanInSalaryMode() {
        let categories = makeBuiltInCategories()
        let utilities = findCategory("utilities", in: categories)
        // Платежи по месяцам: июнь 10k, июль 20k, август 30k, сентябрь 90k.
        let entries = [
            makeBudgetEntry("05.06.2026", .expense, 10_000, categoryId: "utilities"),
            makeBudgetEntry("05.07.2026", .expense, 20_000, categoryId: "utilities"),
            makeBudgetEntry("05.08.2026", .expense, 30_000, categoryId: "utilities"),
            makeBudgetEntry("05.09.2026", .expense, 90_000, categoryId: "utilities"),
        ]
        let salaryEvents = [makeSalaryEvent("30.08.2026", .salary), makeSalaryEvent("30.09.2026", .salary)]
        let today = makeDay("10.10.2026")
        let currentPeriod = makePeriod(containing: today, mode: .salaryMonth, salaryEvents: salaryEvents)

        let rows = makeLimitRows(categories: categories, kind: .obligatory, entries: entries, before: currentPeriod.start, monthCount: 3)
        let utilitiesRow = rows.first { row in row.category.id == "utilities" }
        let homePlan = calculatePlannedAmount(category: utilities, period: currentPeriod, mode: .salaryMonth, entries: entries)

        // Период с 30 сентября: полные месяцы июнь–август, медиана 20k, а не июль–сентябрь (30k).
        #expect(currentPeriod.start == makeDay("30.09.2026"))
        #expect(utilitiesRow?.plannedMonthly == homePlan)
        #expect(homePlan == 20_000)
    }

    @Test func sliderMaximumCoversAverageMinimumAndCurrentLimit() {
        #expect(calculateLimitSliderMaximum(averageMonthly: 56_300, currentLimit: nil, minimumTenge: 10_000, stepTenge: 1_000) == 113_000)
        #expect(calculateLimitSliderMaximum(averageMonthly: 0, currentLimit: nil, minimumTenge: 10_000, stepTenge: 1_000) == 10_000)
        #expect(calculateLimitSliderMaximum(averageMonthly: 20_000, currentLimit: 90_000, minimumTenge: 10_000, stepTenge: 1_000) == 90_000)
    }

    @Test func savingsOnlyWhenLimitBelowAverage() {
        #expect(calculateLimitSavings(averageMonthly: 56_000, monthlyLimit: 45_000) == LimitSavings(perMonth: 11_000, perYear: 132_000))
        #expect(calculateLimitSavings(averageMonthly: 24_752.5, monthlyLimit: 20_000) == LimitSavings(perMonth: 4_752, perYear: 57_024))
        #expect(calculateLimitSavings(averageMonthly: 56_000, monthlyLimit: 56_000) == nil)
        #expect(calculateLimitSavings(averageMonthly: 56_000, monthlyLimit: 70_000) == nil)
    }

    @Test func periodLabelNamesMonthOrStartDay() {
        #expect(formatPeriodLabel(makeOctober2026()) == "окт")
        #expect(formatPeriodLabel(Period(start: makeDay("10.09.2026"), endExclusive: makeDay("09.10.2026"))) == "10 сен")
    }
}

private func findCategory(_ id: String, in categories: [SpendingCategory]) -> SpendingCategory {
    guard let category = categories.first(where: { category in category.id == id }) else {
        preconditionFailure("Нет категории \(id) в тесте")
    }
    return category
}

private func makeTitledEntry(_ title: String, _ amountTenge: Decimal) -> JournalEntry {
    let entry = makeBudgetEntry("05.10.2026", .expense, amountTenge, categoryId: "groceries")
    entry.title = title
    return entry
}
