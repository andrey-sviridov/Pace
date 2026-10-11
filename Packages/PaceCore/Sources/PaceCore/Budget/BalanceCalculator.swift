import Foundation

/// Остаток счёта = остаток в точке отсчёта + Σ влияющих записей по счёту (спека §5.9).
public func calculateBalance(account: Account, entries: [JournalEntry]) -> Decimal {
    let affectingEntries = entries.filter { entry in entry.affectsBalance && entry.mergedInto == nil }
    return affectingEntries.reduce(account.anchorBalance) { balance, entry in
        balance + calculateBalanceChange(of: entry, account: account)
    }
}

/// Как запись меняет остаток счёта: перемещение — минус на источнике, плюс на получателе.
private func calculateBalanceChange(of entry: JournalEntry, account: Account) -> Decimal {
    let isFromAccount = entry.account === account
    let isToAccount = entry.counterAccount === account

    switch entry.type {
    case .expense:
        return isFromAccount ? -(entry.amount + entry.feeAmount) : 0
    case .income:
        return isFromAccount ? entry.amount : 0
    case .transfer:
        let outgoing = isFromAccount ? -(entry.amount + entry.feeAmount) : 0
        let incoming = isToAccount ? entry.amount : 0
        return outgoing + incoming
    case .adjustment:
        // makeAdjustment создаёт доход или расход, направления у этого типа нет — остаток он не меняет.
        return 0
    }
}

/// Запись-корректировка на разницу между фактическим и посчитанным остатком; разницы нет — nil.
public func makeAdjustment(account: Account, actualBalance: Decimal, currentBalance: Decimal, day: CalendarDay) -> JournalEntry? {
    let difference = actualBalance - currentBalance
    guard difference != 0 else { return nil }

    // Депозит растёт сам только от процентов, поэтому его плюс — доход «Проценты по депозиту».
    let isDepositInterest = difference > 0 && account.kind == .deposit
    return JournalEntry(
        day: day,
        type: difference > 0 ? .income : .expense,
        amount: abs(difference),
        account: account,
        title: isDepositInterest ? "Проценты по депозиту" : "Корректировка",
        categoryId: isDepositInterest ? "depositInterest" : "adjustment",
        isReviewed: true,
        affectsBalance: true
    )
}
