import Foundation
import Testing
@testable import KopilkaCore

@Suite struct BalanceCalculatorTests {
    private func makeCard() -> Account {
        Account(kind: .card, title: "Карта *2936", number: "KZ1", anchorBalance: Decimal(string: "6933.41")!, anchorDay: makeDay("01.10.2026"))
    }

    private func makeDeposit() -> Account {
        Account(kind: .deposit, title: "Депозит", number: "KZ2", anchorBalance: 500_000, anchorDay: makeDay("01.10.2026"))
    }

    @Test func balanceIsAnchorPlusAffectingEntries() {
        let card = makeCard()
        let entries = [
            makeBudgetEntry("05.10.2026", .expense, 1_398, categoryId: "groceries", account: card),
            // Старая покупка до точки отсчёта: импорт ставит ей affectsBalance = false.
            makeBudgetEntry("20.09.2026", .expense, 5_000, categoryId: "groceries", account: card, affectsBalance: false),
        ]
        #expect(calculateBalance(account: card, entries: entries) == Decimal(string: "5535.41")!)
    }

    @Test func expenseSubtractsFeeAndIncomeAdds() {
        let card = makeCard()
        let other = makeDeposit()
        let entries = [
            makeBudgetEntry("05.10.2026", .expense, 1_000, categoryId: "groceries", account: card, feeTenge: 50),
            makeBudgetEntry("06.10.2026", .income, 2_000, categoryId: "incomingTransfers", account: card),
            makeBudgetEntry("06.10.2026", .income, 9_000, categoryId: "salary", account: other),
        ]
        #expect(calculateBalance(account: card, entries: entries) == Decimal(string: "7883.41")!)
    }

    @Test func transferToDepositMovesMoneyBetweenAccounts() {
        let card = makeCard()
        let deposit = makeDeposit()
        let transfer = makeBudgetEntry("05.10.2026", .transfer, 3_000, categoryId: "ownTransfer", account: card, counterAccount: deposit, feeTenge: 100)

        #expect(calculateBalance(account: card, entries: [transfer]) == Decimal(string: "3833.41")!)
        #expect(calculateBalance(account: deposit, entries: [transfer]) == 503_000)
    }

    @Test func mergedEntriesDoNotCountTwice() {
        let card = makeCard()
        let merged = makeBudgetEntry("05.10.2026", .expense, 1_398, categoryId: "groceries", account: card)
        let kept = makeBudgetEntry("05.10.2026", .expense, 1_398, categoryId: "groceries", account: card)
        merged.mergedInto = kept
        #expect(calculateBalance(account: card, entries: [kept, merged]) == Decimal(string: "5535.41")!)
    }

    @Test func depositSurplusBecomesInterestIncome() {
        let deposit = makeDeposit()
        let actual = Decimal(string: "507881.99")!

        let adjustment = makeAdjustment(account: deposit, actualBalance: actual, currentBalance: 500_000, day: makeDay("09.10.2026"))

        #expect(adjustment?.type == .income)
        #expect(adjustment?.categoryId == "depositInterest")
        #expect(adjustment?.title == "Проценты по депозиту")
        #expect(adjustment?.amount == Decimal(string: "7881.99")!)
        #expect(adjustment?.account === deposit)
        #expect(adjustment?.affectsBalance == true)
        #expect(adjustment?.isReviewed == true)
        #expect(adjustment.map { entry in calculateBalance(account: deposit, entries: [entry]) } == actual)
    }

    @Test func cardDifferenceBecomesAdjustment() {
        let card = makeCard()
        let surplus = makeAdjustment(account: card, actualBalance: 7_000, currentBalance: 6_000, day: makeDay("09.10.2026"))
        let shortage = makeAdjustment(account: card, actualBalance: 5_500, currentBalance: 6_000, day: makeDay("09.10.2026"))

        #expect(surplus?.type == .income)
        #expect(surplus?.categoryId == "adjustment")
        #expect(surplus?.title == "Корректировка")
        #expect(surplus?.amount == 1_000)
        #expect(shortage?.type == .expense)
        #expect(shortage?.categoryId == "adjustment")
        #expect(shortage?.amount == 500)
    }

    @Test func depositShortageIsAdjustmentNotInterest() {
        let shortage = makeAdjustment(account: makeDeposit(), actualBalance: 400_000, currentBalance: 500_000, day: makeDay("09.10.2026"))
        #expect(shortage?.type == .expense)
        #expect(shortage?.categoryId == "adjustment")
    }

    @Test func noDifferenceMeansNoAdjustment() {
        #expect(makeAdjustment(account: makeCard(), actualBalance: 6_000, currentBalance: 6_000, day: makeDay("09.10.2026")) == nil)
    }

    @Test func adjustmentDoesNotChangeBudget() {
        let card = makeCard()
        let entries = [
            makeAdjustment(account: card, actualBalance: 7_000, currentBalance: 6_000, day: makeDay("09.10.2026")),
            makeAdjustment(account: card, actualBalance: 5_000, currentBalance: 6_000, day: makeDay("09.10.2026")),
        ].compactMap { entry in entry }

        let summary = calculateBudget(
            period: makeOctober2026(), today: makeDay("10.10.2026"), mode: .calendarMonth,
            entries: entries, categories: makeBuiltInCategories(), salaryEvents: [], monthlySavingsGoal: 0
        )
        #expect(summary.incomeTotal == 0)
        #expect(summary.flexibleSpent == 0)
    }
}
