import Foundation
@testable import PaceCore

/// Общие заготовки для тестов бюджета, остатков и аналитики.
func makeDay(_ dotted: String) -> CalendarDay {
    guard let day = CalendarDay(dotted: dotted) else { preconditionFailure("Неверная дата в тесте: \(dotted)") }
    return day
}

func makeBudgetEntry(
    _ dotted: String,
    _ type: EntryType,
    _ amountTenge: Decimal,
    categoryId: String?,
    account: Account? = nil,
    counterAccount: Account? = nil,
    feeTenge: Decimal = 0,
    affectsBalance: Bool = true
) -> JournalEntry {
    JournalEntry(
        day: makeDay(dotted),
        type: type,
        amount: amountTenge,
        feeAmount: feeTenge,
        account: account,
        counterAccount: counterAccount,
        title: "Тестовая запись",
        categoryId: categoryId,
        affectsBalance: affectsBalance
    )
}

func makeSalaryEvent(_ dotted: String, _ kind: SalaryEventKind, _ amountTenge: Decimal = 400_000, isOneOff: Bool = false) -> SalaryEvent {
    SalaryEvent(day: makeDay(dotted), amount: amountTenge, kind: kind, isOneOff: isOneOff)
}

func makeOctober2026() -> Period {
    Period(start: makeDay("01.10.2026"), endExclusive: makeDay("01.11.2026"))
}
