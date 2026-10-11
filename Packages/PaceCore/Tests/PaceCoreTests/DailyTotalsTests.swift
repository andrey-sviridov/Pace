import Foundation
import Testing
@testable import PaceCore

@Suite struct DailyTotalsTests {
    @Test func dailyTotalsCountLikeBudgetAndSkipTransfers() {
        let categories = makeBuiltInCategories()
        let merged = makeBudgetEntry("05.10.2026", .expense, 9_999, categoryId: "groceries")
        merged.mergedInto = makeBudgetEntry("05.10.2026", .expense, 1, categoryId: "groceries")
        let entries = [
            makeBudgetEntry("05.10.2026", .expense, 1_500, categoryId: "groceries"),
            makeBudgetEntry("15.10.2026", .income, 402_487, categoryId: "salary"),
            // Перевод на депозит — не трата, но его комиссия — трата «Комиссии банка».
            makeBudgetEntry("15.10.2026", .transfer, 100_000, categoryId: "ownTransfer", feeTenge: 250),
            makeBudgetEntry("01.11.2026", .expense, 700, categoryId: "groceries"),
            merged,
        ]
        let month = makeCalendarMonth(containing: makeDay("12.10.2026"))

        let totals = calculateDailyTotals(month: month, entries: entries, categories: categories)

        #expect(totals[makeDay("05.10.2026")] == DayTotals(income: 0, spending: 1_500))
        #expect(totals[makeDay("15.10.2026")] == DayTotals(income: 402_487, spending: 250))
        #expect(totals[makeDay("01.11.2026")] == nil)
        #expect(totals.count == 2)
    }

    @Test func monthGridStartsOnMonday() {
        // 1 сентября 2026 — вторник: перед ним одна пустая клетка.
        let month = makeCalendarMonth(containing: makeDay("15.09.2026"))

        let cells = makeMonthGridCells(month: month)

        #expect(cells.count == 31)
        #expect(cells[0] == nil)
        #expect(cells[1] == makeDay("01.09.2026"))
        #expect(cells[30] == makeDay("30.09.2026"))
    }

    @Test func monthTitleIsNominative() {
        #expect(formatMonthTitle(makeCalendarMonth(containing: makeDay("15.09.2026"))) == "Сентябрь 2026")
    }
}
