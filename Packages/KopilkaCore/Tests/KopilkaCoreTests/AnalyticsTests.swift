import Foundation
import Testing
@testable import KopilkaCore

@Suite struct AnalyticsTests {
    private let categories = makeBuiltInCategories()

    @Test func cumulativeSpendingRunsUntilToday() {
        let entries = [
            makeBudgetEntry("01.10.2026", .expense, 1_000, categoryId: "groceries"),
            makeBudgetEntry("02.10.2026", .expense, 5_000, categoryId: "mortgage"),
            makeBudgetEntry("03.10.2026", .income, 200, categoryId: "groceries"),
            makeBudgetEntry("03.10.2026", .transfer, 9_000, categoryId: "ownTransfer"),
            makeBudgetEntry("04.10.2026", .expense, 7_000, categoryId: "groceries"),
        ]

        let series = calculateCumulativeSpending(period: makeOctober2026(), today: makeDay("03.10.2026"), entries: entries, categories: categories)

        #expect(series.map { point in point.day } == [makeDay("01.10.2026"), makeDay("02.10.2026"), makeDay("03.10.2026")])
        #expect(series.map { point in point.total } == [1_000, 6_000, 5_800])
        #expect(series.map { point in point.obligatoryTotal } == [0, 5_000, 5_000])
    }

    @Test func cumulativeSpendingCoversWholePastPeriod() {
        let series = calculateCumulativeSpending(period: makeOctober2026(), today: makeDay("05.11.2026"), entries: [], categories: categories)
        #expect(series.count == 31)
        #expect(series.last?.total == 0)
    }

    @Test func spendingByCategoryIsSortedAndPositive() {
        let entries = [
            makeBudgetEntry("01.10.2026", .expense, 3_000, categoryId: "groceries"),
            makeBudgetEntry("02.10.2026", .expense, 5_000, categoryId: "cafes"),
            makeBudgetEntry("02.10.2026", .expense, 1_000, categoryId: nil),
            makeBudgetEntry("03.10.2026", .expense, 2_000, categoryId: "transport"),
            makeBudgetEntry("04.10.2026", .income, 2_000, categoryId: "transport"),
            makeBudgetEntry("04.10.2026", .income, 400_000, categoryId: "salary"),
            makeBudgetEntry("05.09.2026", .expense, 8_000, categoryId: "groceries"),
        ]

        let spending = calculateSpendingByCategory(period: makeOctober2026(), entries: entries, categories: categories)

        #expect(spending.map { item in item.categoryId } == ["cafes", "groceries", "uncategorized"])
        #expect(spending.map { item in item.total } == [5_000, 3_000, 1_000])
    }

    @Test func monthlyLeftoverIsIncomeMinusSpending() {
        let september = Period(start: makeDay("01.09.2026"), endExclusive: makeDay("01.10.2026"))
        let entries = [
            makeBudgetEntry("10.09.2026", .income, 400_000, categoryId: "salary"),
            makeBudgetEntry("11.09.2026", .expense, 200_000, categoryId: "mortgage"),
            makeBudgetEntry("12.09.2026", .expense, 50_000, categoryId: "groceries"),
            makeBudgetEntry("12.09.2026", .income, 3_000, categoryId: "depositInterest"),
            makeBudgetEntry("10.10.2026", .income, 300_000, categoryId: "salary"),
            makeBudgetEntry("11.10.2026", .expense, 350_000, categoryId: "groceries"),
        ]

        let leftovers = calculateMonthlyLeftover(months: [september, makeOctober2026()], entries: entries, categories: categories)

        #expect(leftovers.map { item in item.period } == [september, makeOctober2026()])
        #expect(leftovers.map { item in item.leftover } == [150_000, -50_000])
    }

    @Test func categoryHistoryFollowsPeriodOrder() {
        let september = Period(start: makeDay("01.09.2026"), endExclusive: makeDay("01.10.2026"))
        let entries = [
            makeBudgetEntry("10.09.2026", .expense, 4_000, categoryId: "cafes"),
            makeBudgetEntry("10.10.2026", .expense, 6_000, categoryId: "cafes"),
            makeBudgetEntry("11.10.2026", .income, 1_000, categoryId: "cafes"),
            makeBudgetEntry("11.10.2026", .expense, 9_000, categoryId: "groceries"),
        ]

        let history = calculateCategoryHistory(categoryId: "cafes", periods: [makeOctober2026(), september], entries: entries, categories: categories)

        #expect(history == [5_000, 4_000])
    }
}
