import Foundation

// Единые правила «что считать тратой и доходом» для бюджета, лимитов и аналитики.

/// Часть траты записи, отнесённая к одной категории.
struct SpendingPart {
    let categoryId: String
    let kind: CategoryKind
    let amount: Decimal
}

/// Записи периода без слитых дублей: слитая запись уже учтена в той, куда её склеили.
func findPeriodEntries(_ entries: [JournalEntry], period: Period) -> [JournalEntry] {
    entries.filter { entry in entry.mergedInto == nil && period.contains(entry.day) }
}

func makeCategoryKindsById(_ categories: [SpendingCategory]) -> [String: CategoryKind] {
    Dictionary(categories.map { category in (category.id, category.kind) }, uniquingKeysWith: { first, _ in first })
}

/// Вид категории записи. Без категории или с неизвестной категорией:
/// расход — гибкая трата, поступление — доход (а не возврат, уменьшающий траты).
func findCategoryKind(of entry: JournalEntry, kindsById: [String: CategoryKind]) -> CategoryKind {
    if let categoryId = entry.categoryId, let kind = kindsById[categoryId] { return kind }
    return entry.type == .income ? .income : .flexible
}

/// Из чего складываются траты записи: сама сумма в своей категории и комиссия.
func makeSpendingParts(of entry: JournalEntry, kindsById: [String: CategoryKind]) -> [SpendingPart] {
    let kind = findCategoryKind(of: entry, kindsById: kindsById)
    let mainPart = SpendingPart(
        categoryId: entry.categoryId ?? "uncategorized",
        kind: kind,
        amount: calculateSpendingAmount(of: entry, kind: kind)
    )
    guard let feePart = makeBankFeePart(of: entry, kindsById: kindsById) else { return [mainPart] }
    return [mainPart, feePart]
}

/// Вклад записи в траты её категории: покупка — плюс, возврат в ту же категорию — минус.
/// Перемещения и категории дохода/перемещения тратами не являются.
func calculateSpendingAmount(of entry: JournalEntry, kind: CategoryKind) -> Decimal {
    guard kind == .obligatory || kind == .flexible else { return 0 }
    switch entry.type {
    case .expense: return entry.amount
    case .income: return -entry.amount
    case .transfer, .adjustment: return 0
    }
}

/// Комиссия расхода или перемещения — трата в «Комиссии банка» (спека §5.3), даже если само перемещение не трата.
func makeBankFeePart(of entry: JournalEntry, kindsById: [String: CategoryKind]) -> SpendingPart? {
    guard entry.type == .expense || entry.type == .transfer, entry.feeAmount > 0 else { return nil }
    return SpendingPart(categoryId: "bankFees", kind: kindsById["bankFees"] ?? .flexible, amount: entry.feeAmount)
}

/// Вклад записи в доход периода.
func calculateIncomeAmount(of entry: JournalEntry, kind: CategoryKind) -> Decimal {
    guard entry.type == .income, kind == .income else { return 0 }
    // Проценты остаются на депозите, свободными деньгами на карте они не становятся.
    guard entry.categoryId != "depositInterest" else { return 0 }
    return entry.amount
}

/// Сумма трат записей в категориях видов `kinds`.
func calculateSpending(of entries: [JournalEntry], kinds: [CategoryKind], kindsById: [String: CategoryKind]) -> Decimal {
    let parts = entries.flatMap { entry in makeSpendingParts(of: entry, kindsById: kindsById) }
    return parts
        .filter { part in kinds.contains(part.kind) }
        .reduce(Decimal(0)) { total, part in total + part.amount }
}

/// Траты одной категории; записи без категории идут в "uncategorized".
func calculateCategorySpending(categoryId: String, entries: [JournalEntry], kindsById: [String: CategoryKind]) -> Decimal {
    let parts = entries.flatMap { entry in makeSpendingParts(of: entry, kindsById: kindsById) }
    return parts
        .filter { part in part.categoryId == categoryId }
        .reduce(Decimal(0)) { total, part in total + part.amount }
}

/// Фактический доход записей.
func calculateActualIncome(of entries: [JournalEntry], kindsById: [String: CategoryKind]) -> Decimal {
    entries.reduce(Decimal(0)) { total, entry in
        total + calculateIncomeAmount(of: entry, kind: findCategoryKind(of: entry, kindsById: kindsById))
    }
}
