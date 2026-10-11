import Foundation
import Testing
@testable import PaceCore

@Suite struct HomeNumbersTests {
    private let nonBreakingSpace = "\u{00A0}"
    private let today = makeDay("10.10.2026")

    /// Как у пользователя: ~402k 15-го (аванс) и 30-го (зарплата).
    private func makeSalaryHistory() -> [JournalEntry] {
        [
            makeBudgetEntry("15.08.2026", .income, 402_488, categoryId: "salary"),
            makeBudgetEntry("30.08.2026", .income, 402_487, categoryId: "salary"),
            makeBudgetEntry("15.09.2026", .income, 402_488, categoryId: "salary"),
            makeBudgetEntry("30.09.2026", .income, 402_487, categoryId: "salary"),
        ]
    }

    private func makeCategories() -> [SpendingCategory] {
        [
            SpendingCategory(id: "salary", name: "Зарплата", iconName: "", kind: .income),
            SpendingCategory(id: "groceries", name: "Продукты", iconName: "", kind: .flexible),
        ]
    }

    private func calculate(mode: PeriodMode, spentTenge: Decimal) -> HomeNumbers {
        let entries = makeSalaryHistory() + [makeBudgetEntry("05.10.2026", .expense, spentTenge, categoryId: "groceries")]
        let salaryEvents = findSalaryEvents(entries: entries, advanceDayRange: 10...20, oneOffAboveMedianTimes: 1.5)
        return calculateHomeNumbers(
            today: today,
            mode: mode,
            monthlySavingsGoal: 0,
            entries: entries,
            categories: makeCategories(),
            accounts: [],
            salaryEvents: salaryEvents
        )
    }

    @Test func salaryMonthCaption() {
        // Доход 402 487 факт + 402 488 ожидаемый аванс = 804 975; свободно 288 610,92 на 20 дней.
        let numbers = calculate(mode: .salaryMonth, spentTenge: Decimal(string: "516364.08")!)
        #expect(numbers.budget.freeToSpend == Decimal(string: "288610.92")!)
        #expect(makeHeroTitle(numbers: numbers) == "Можно потратить до зарплаты")
        #expect(makeHeroCaption(numbers: numbers) == "зарплата ~30 окт · 20 дней · ≈14\(nonBreakingSpace)430 ₸ в день")
        #expect(makeHeroAmount(freeToSpend: numbers.budget.freeToSpend) == 288_610)
    }

    @Test func calendarMonthCaptionEndsOnLastDay() {
        let numbers = calculate(mode: .calendarMonth, spentTenge: 100_000)
        #expect(makeHeroTitle(numbers: numbers) == "Можно потратить до конца месяца")
        #expect(makeHeroCaption(numbers: numbers).hasPrefix("по 31 окт · 22 дня · ≈"))
    }

    @Test func halfMonthEndsWithAdvance() {
        let numbers = calculate(mode: .halfMonth, spentTenge: 100_000)
        #expect(makeHeroTitle(numbers: numbers) == "Можно потратить до аванса")
        #expect(makeHeroCaption(numbers: numbers).hasPrefix("аванс ~15 окт · 5 дней · ≈"))
    }

    @Test func overspendHasNoPerDay() {
        let numbers = calculate(mode: .salaryMonth, spentTenge: Decimal(string: "809975.30")!)
        #expect(numbers.budget.freeToSpend == Decimal(string: "-5000.30")!)
        #expect(makeHeroTitle(numbers: numbers) == "Перерасход до зарплаты")
        #expect(makeHeroCaption(numbers: numbers) == "зарплата ~30 окт · 20 дней")
        #expect(makeHeroAmount(freeToSpend: numbers.budget.freeToSpend) == 5_001)
    }

    @Test func countsOnlyUnreviewedVisibleEntries() {
        let reviewed = makeBudgetEntry("01.10.2026", .expense, 100, categoryId: "groceries")
        reviewed.isReviewed = true
        let unreviewed = makeBudgetEntry("02.10.2026", .expense, 100, categoryId: "groceries")
        let merged = makeBudgetEntry("02.10.2026", .expense, 100, categoryId: "groceries")
        merged.mergedInto = unreviewed

        #expect(isAwaitingReview(unreviewed))
        #expect(!isAwaitingReview(reviewed))
        #expect(!isAwaitingReview(merged))
    }

    @Test func balancesSumByAccountKind() {
        let card = Account(kind: .card, title: "Карта", number: "1", anchorBalance: 1_000)
        let deposit = Account(kind: .deposit, title: "Депозит", number: "2", anchorBalance: 250_000)
        let otherCard = Account(kind: .ownOtherCard, title: "Kaspi", number: "3", anchorBalance: 7)
        let spending = makeBudgetEntry("05.10.2026", .expense, 300, categoryId: "groceries", account: card)
        let numbers = calculateHomeNumbers(
            today: today,
            mode: .calendarMonth,
            monthlySavingsGoal: 0,
            entries: [spending],
            categories: makeCategories(),
            accounts: [card, deposit, otherCard],
            salaryEvents: []
        )
        #expect(numbers.cardBalance == 700)
        #expect(numbers.depositBalance == 250_000)
        #expect(numbers.unreviewedCount == 1)
    }
}
