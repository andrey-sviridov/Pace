import Foundation
import Testing
@testable import KopilkaCore

@Suite struct BudgetCalculatorTests {
    private func makeCategories(mortgagePlan: Decimal? = nil, loansPlan: Decimal? = nil) -> [SpendingCategory] {
        let categories = makeBuiltInCategories()
        categories.first { category in category.id == "mortgage" }?.expectedMonthlyAmount = mortgagePlan
        categories.first { category in category.id == "loans" }?.expectedMonthlyAmount = loansPlan
        return categories
    }

    // MARK: - Главная цифра

    @Test func freeToSpendFollowsSpecFormula() {
        let merged = makeBudgetEntry("12.10.2026", .expense, 99_999, categoryId: "groceries")
        merged.mergedInto = makeBudgetEntry("12.10.2026", .expense, 99_999, categoryId: "groceries")
        let entries = [
            // Доход 805 000; проценты по депозиту не свободные деньги.
            makeBudgetEntry("15.10.2026", .income, 405_000, categoryId: "salary"),
            makeBudgetEntry("20.10.2026", .income, 400_000, categoryId: "incomingTransfers"),
            makeBudgetEntry("20.10.2026", .income, 7_000, categoryId: "depositInterest"),
            // Обязательные: план 200 000 + 104 000, факт 200 000 + 80 000.
            makeBudgetEntry("05.10.2026", .expense, 200_000, categoryId: "mortgage"),
            makeBudgetEntry("10.10.2026", .expense, 80_000, categoryId: "loans"),
            // Гибкие: 150 000 − возврат 10 000 + 70 000 + без категории 5 000 = 215 000.
            makeBudgetEntry("11.10.2026", .expense, 150_000, categoryId: "groceries"),
            makeBudgetEntry("13.10.2026", .income, 10_000, categoryId: "groceries"),
            makeBudgetEntry("14.10.2026", .expense, 70_000, categoryId: "cafes"),
            makeBudgetEntry("15.10.2026", .expense, 5_000, categoryId: nil),
            // Не траты и не доход.
            makeBudgetEntry("16.10.2026", .transfer, 50_000, categoryId: "ownTransfer"),
            makeBudgetEntry("17.10.2026", .expense, 3_000, categoryId: "adjustment"),
            makeBudgetEntry("30.09.2026", .expense, 12_345, categoryId: "groceries"),
            merged,
        ]

        let summary = calculateBudget(
            period: makeOctober2026(),
            today: makeDay("26.10.2026"),
            mode: .calendarMonth,
            entries: entries,
            categories: makeCategories(mortgagePlan: 200_000, loansPlan: 104_000),
            salaryEvents: [],
            monthlySavingsGoal: 100_000
        )

        #expect(summary.incomeTotal == 805_000)
        #expect(summary.obligatoryTotal == 304_000)
        #expect(summary.savingsGoal == 100_000)
        #expect(summary.flexibleSpent == 215_000)
        #expect(summary.freeToSpend == 186_000)
        #expect(summary.daysLeft == 6)
        #expect(summary.perDay == 31_000)
    }

    @Test func obligatoryTakesFactWhenItExceedsPlan() {
        let entries = [makeBudgetEntry("05.10.2026", .expense, 230_000, categoryId: "mortgage")]
        let summary = calculateBudget(
            period: makeOctober2026(), today: makeDay("10.10.2026"), mode: .calendarMonth,
            entries: entries, categories: makeCategories(mortgagePlan: 200_000),
            salaryEvents: [], monthlySavingsGoal: 0
        )
        #expect(summary.obligatoryTotal == 230_000)
    }

    @Test func expectedSalaryAndAdvanceCountUntilTheyArrive() {
        let events = [
            makeSalaryEvent("15.08.2026", .advance),
            makeSalaryEvent("30.08.2026", .salary),
            makeSalaryEvent("15.09.2026", .advance),
            makeSalaryEvent("30.09.2026", .salary),
        ]
        let entries = [makeBudgetEntry("30.09.2026", .income, 400_000, categoryId: "salary")]
        let period = Period(start: makeDay("30.09.2026"), endExclusive: makeDay("30.10.2026"))

        let summary = calculateBudget(
            period: period, today: makeDay("09.10.2026"), mode: .salaryMonth,
            entries: entries, categories: makeCategories(), salaryEvents: events, monthlySavingsGoal: 0
        )

        // Зарплата 30.09 уже пришла, аванс 15.10 ожидается.
        #expect(summary.incomeTotal == 800_000)
    }

    @Test func halfMonthHalvesGoalAndPlacesObligatoryInItsHalf() {
        let history = [makeBudgetEntry("05.09.2026", .expense, 200_000, categoryId: "mortgage")]
        let categories = makeCategories(mortgagePlan: 200_000)
        let halfWithPayment = Period(start: makeDay("30.09.2026"), endExclusive: makeDay("15.10.2026"))
        let halfWithoutPayment = Period(start: makeDay("15.10.2026"), endExclusive: makeDay("30.10.2026"))

        let first = calculateBudget(
            period: halfWithPayment, today: makeDay("01.10.2026"), mode: .halfMonth,
            entries: history, categories: categories, salaryEvents: [], monthlySavingsGoal: 100_000
        )
        let second = calculateBudget(
            period: halfWithoutPayment, today: makeDay("16.10.2026"), mode: .halfMonth,
            entries: history, categories: categories, salaryEvents: [], monthlySavingsGoal: 100_000
        )

        #expect(first.savingsGoal == 50_000)
        #expect(first.obligatoryTotal == 200_000)
        #expect(second.obligatoryTotal == 0)
    }

    @Test func perDayRoundsDownAndIsZeroWhenOverspent() {
        let income = [makeBudgetEntry("01.10.2026", .income, 100_000, categoryId: "salary")]
        let overspent = income + [makeBudgetEntry("02.10.2026", .expense, 150_000, categoryId: "groceries")]

        let rounded = calculateBudget(
            period: makeOctober2026(), today: makeDay("29.10.2026"), mode: .calendarMonth,
            entries: income, categories: makeCategories(), salaryEvents: [], monthlySavingsGoal: 0
        )
        let negative = calculateBudget(
            period: makeOctober2026(), today: makeDay("29.10.2026"), mode: .calendarMonth,
            entries: overspent, categories: makeCategories(), salaryEvents: [], monthlySavingsGoal: 0
        )

        #expect(rounded.daysLeft == 3)
        #expect(rounded.perDay == 33_333)
        #expect(negative.freeToSpend == -50_000)
        #expect(negative.perDay == 0)
    }

    @Test func daysLeftIsAtLeastOne() {
        let summary = calculateBudget(
            period: makeOctober2026(), today: makeDay("05.11.2026"), mode: .calendarMonth,
            entries: [], categories: makeCategories(), salaryEvents: [], monthlySavingsGoal: 0
        )
        #expect(summary.daysLeft == 1)
    }

    @Test func uncategorizedIncomeIsIncomeNotRefund() {
        let base = [makeBudgetEntry("05.10.2026", .expense, 20_000, categoryId: "groceries")]
        let withIncome = base + [
            makeBudgetEntry("06.10.2026", .income, 5_000, categoryId: nil),
            makeBudgetEntry("07.10.2026", .income, 1_000, categoryId: "unknownCategory"),
        ]

        let before = calculateBudget(
            period: makeOctober2026(), today: makeDay("10.10.2026"), mode: .calendarMonth,
            entries: base, categories: makeCategories(), salaryEvents: [], monthlySavingsGoal: 0
        )
        let after = calculateBudget(
            period: makeOctober2026(), today: makeDay("10.10.2026"), mode: .calendarMonth,
            entries: withIncome, categories: makeCategories(), salaryEvents: [], monthlySavingsGoal: 0
        )

        #expect(after.incomeTotal == before.incomeTotal + 6_000)
        #expect(after.flexibleSpent == before.flexibleSpent)
    }

    @Test func feesAreBankFeesSpending() {
        let card = Account(kind: .card, title: "Карта", number: "KZ1")
        let deposit = Account(kind: .deposit, title: "Депозит", number: "KZ2")
        let entries = [
            makeBudgetEntry("05.10.2026", .transfer, 30_000, categoryId: "ownTransfer", account: card, counterAccount: deposit, feeTenge: 250),
            makeBudgetEntry("06.10.2026", .expense, 10_000, categoryId: "transfersToPeople", account: card, feeTenge: 100),
        ]
        let categories = makeCategories()
        categories.first { category in category.id == "bankFees" }?.monthlyLimit = 1_000

        let summary = calculateBudget(
            period: makeOctober2026(), today: makeDay("10.10.2026"), mode: .calendarMonth,
            entries: entries, categories: categories, salaryEvents: [], monthlySavingsGoal: 0
        )
        let statuses = calculateLimitStatuses(
            period: makeOctober2026(), today: makeDay("10.10.2026"), mode: .calendarMonth,
            entries: entries, categories: categories
        )

        // Само перемещение не трата, его комиссия — трата; у покупки сумма и комиссия идут в разные категории.
        #expect(summary.flexibleSpent == 10_350)
        #expect(statuses.first { status in status.category.id == "bankFees" }?.spent == 350)
    }

    // MARK: - Типичная сумма обязательной категории

    @Test func typicalMonthlyAmountIsMedianOfLastFullMonths() {
        let entries = [
            makeBudgetEntry("10.06.2026", .expense, 999_999, categoryId: "utilities"),
            makeBudgetEntry("10.07.2026", .expense, 20_000, categoryId: "utilities"),
            makeBudgetEntry("10.08.2026", .expense, 30_000, categoryId: "utilities"),
            makeBudgetEntry("10.09.2026", .expense, 25_000, categoryId: "utilities"),
            makeBudgetEntry("10.09.2026", .expense, 77_777, categoryId: "groceries"),
        ]

        let fromOctober = calculateTypicalMonthlyAmount(categoryId: "utilities", entries: entries, before: makeDay("01.10.2026"), monthCount: 3)
        // 30.09 — сентябрь ещё не полный, берутся июнь–август.
        let fromSalaryDay = calculateTypicalMonthlyAmount(categoryId: "utilities", entries: entries, before: makeDay("30.09.2026"), monthCount: 3)
        let withoutHistory = calculateTypicalMonthlyAmount(categoryId: "mortgage", entries: entries, before: makeDay("01.10.2026"), monthCount: 3)

        #expect(fromOctober == 25_000)
        #expect(fromSalaryDay == 30_000)
        #expect(withoutHistory == 0)
    }

    @Test func obligatoryPlanFallsBackToTypicalAmount() {
        let entries = [
            makeBudgetEntry("10.07.2026", .expense, 20_000, categoryId: "utilities"),
            makeBudgetEntry("10.08.2026", .expense, 30_000, categoryId: "utilities"),
            makeBudgetEntry("10.09.2026", .expense, 25_000, categoryId: "utilities"),
        ]
        let summary = calculateBudget(
            period: makeOctober2026(), today: makeDay("05.10.2026"), mode: .calendarMonth,
            entries: entries, categories: makeCategories(), salaryEvents: [], monthlySavingsGoal: 0
        )
        #expect(summary.obligatoryTotal == 25_000)
    }

    // MARK: - Лимиты

    private func makeLimitedCategory(_ id: String, limitTenge: Decimal) -> SpendingCategory {
        SpendingCategory(id: id, name: id, iconName: "cart.fill", kind: .flexible, monthlyLimit: limitTenge, warnAtPercent: 85)
    }

    @Test func limitLevelsAtWarnAndOverThresholds() {
        let categories = [
            makeLimitedCategory("groceries", limitTenge: 100_000),
            makeLimitedCategory("cafes", limitTenge: 100_000),
            makeLimitedCategory("transport", limitTenge: 100_000),
            makeLimitedCategory("health", limitTenge: 100_000),
        ]
        let entries = [
            makeBudgetEntry("05.10.2026", .expense, 84_000, categoryId: "groceries"),
            makeBudgetEntry("05.10.2026", .expense, 86_000, categoryId: "cafes"),
            makeBudgetEntry("05.10.2026", .expense, 101_000, categoryId: "transport"),
            makeBudgetEntry("05.10.2026", .expense, 100_000, categoryId: "health"),
        ]

        let statuses = calculateLimitStatuses(
            period: makeOctober2026(), today: makeDay("10.10.2026"), mode: .calendarMonth,
            entries: entries, categories: categories
        )
        let levelsById = Dictionary(uniqueKeysWithValues: statuses.map { status in (status.category.id, status.level) })

        #expect(levelsById["groceries"] == .normal)
        #expect(levelsById["cafes"] == .warning)
        #expect(levelsById["transport"] == .over)
        #expect(levelsById["health"] == .warning)
        #expect(statuses.map { status in status.category.id } == ["transport", "health", "cafes", "groceries"])
    }

    @Test func halfMonthHalvesLimit() {
        let statuses = calculateLimitStatuses(
            period: Period(start: makeDay("30.09.2026"), endExclusive: makeDay("15.10.2026")),
            today: makeDay("01.10.2026"), mode: .halfMonth,
            entries: [], categories: [makeLimitedCategory("groceries", limitTenge: 100_000)]
        )
        #expect(statuses.first?.limit == 50_000)
    }

    @Test func limitSpentSubtractsRefundsAndSkipsMergedAndUnlimited() {
        let merged = makeBudgetEntry("06.10.2026", .expense, 40_000, categoryId: "groceries")
        merged.mergedInto = makeBudgetEntry("06.10.2026", .expense, 40_000, categoryId: "groceries")
        let unlimited = SpendingCategory(id: "cafes", name: "cafes", iconName: "cup.and.saucer.fill", kind: .flexible)
        let entries = [
            makeBudgetEntry("05.10.2026", .expense, 30_000, categoryId: "groceries"),
            makeBudgetEntry("07.10.2026", .income, 5_000, categoryId: "groceries"),
            makeBudgetEntry("07.10.2026", .expense, 9_000, categoryId: "cafes"),
            merged,
        ]

        let statuses = calculateLimitStatuses(
            period: makeOctober2026(), today: makeDay("10.10.2026"), mode: .calendarMonth,
            entries: entries, categories: [makeLimitedCategory("groceries", limitTenge: 100_000), unlimited]
        )

        #expect(statuses.count == 1)
        #expect(statuses.first?.spent == 25_000)
        #expect(statuses.first?.usedShare == 0.25)
    }

    @Test func paceShareIsShareOfPassedDays() {
        let statuses = calculateLimitStatuses(
            period: makeOctober2026(), today: makeDay("10.10.2026"), mode: .calendarMonth,
            entries: [], categories: [makeLimitedCategory("groceries", limitTenge: 100_000)]
        )
        let afterPeriod = calculateLimitStatuses(
            period: makeOctober2026(), today: makeDay("20.11.2026"), mode: .calendarMonth,
            entries: [], categories: [makeLimitedCategory("groceries", limitTenge: 100_000)]
        )
        #expect(statuses.first?.paceShare == 10.0 / 31.0)
        #expect(afterPeriod.first?.paceShare == 1)
    }
}
