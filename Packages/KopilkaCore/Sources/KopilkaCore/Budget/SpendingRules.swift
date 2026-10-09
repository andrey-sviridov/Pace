import Foundation

// Единые правила «что считать тратой и доходом» для бюджета, лимитов и аналитики.

/// Записи периода без слитых дублей: слитая запись уже учтена в той, куда её склеили.
func findPeriodEntries(_ entries: [JournalEntry], period: Period) -> [JournalEntry] {
    entries.filter { entry in entry.mergedInto == nil && period.contains(entry.day) }
}

func makeCategoryKindsById(_ categories: [SpendingCategory]) -> [String: CategoryKind] {
    Dictionary(categories.map { category in (category.id, category.kind) }, uniquingKeysWith: { first, _ in first })
}

/// Вид категории записи. Без категории или с неизвестной категорией запись считается гибкой.
func findCategoryKind(of entry: JournalEntry, kindsById: [String: CategoryKind]) -> CategoryKind {
    guard let categoryId = entry.categoryId, let kind = kindsById[categoryId] else { return .flexible }
    return kind
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

/// Вклад записи в доход периода.
func calculateIncomeAmount(of entry: JournalEntry, kind: CategoryKind) -> Decimal {
    guard entry.type == .income, kind == .income else { return 0 }
    // Проценты остаются на депозите, свободными деньгами на карте они не становятся.
    guard entry.categoryId != "depositInterest" else { return 0 }
    return entry.amount
}

/// Сумма трат записей, чья категория одного из видов `kinds`.
func calculateSpending(of entries: [JournalEntry], kinds: [CategoryKind], kindsById: [String: CategoryKind]) -> Decimal {
    entries.reduce(Decimal(0)) { total, entry in
        let kind = findCategoryKind(of: entry, kindsById: kindsById)
        guard kinds.contains(kind) else { return total }
        return total + calculateSpendingAmount(of: entry, kind: kind)
    }
}

/// Траты одной категории.
func calculateCategorySpending(categoryId: String, entries: [JournalEntry], kindsById: [String: CategoryKind]) -> Decimal {
    entries
        .filter { entry in entry.categoryId == categoryId }
        .reduce(Decimal(0)) { total, entry in
            total + calculateSpendingAmount(of: entry, kind: findCategoryKind(of: entry, kindsById: kindsById))
        }
}

/// Фактический доход записей.
func calculateActualIncome(of entries: [JournalEntry], kindsById: [String: CategoryKind]) -> Decimal {
    entries.reduce(Decimal(0)) { total, entry in
        total + calculateIncomeAmount(of: entry, kind: findCategoryKind(of: entry, kindsById: kindsById))
    }
}
