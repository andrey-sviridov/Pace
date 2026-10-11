import Foundation

/// Стартовые правила для переводов без получателя (спека §5.3), по порядку применения.
public func makeDefaultAmountRules() -> [AmountRule] {
    [
        AmountRule(minAmount: 100_000, maxAmount: 100_000, afterEvent: .salary, windowDays: 3, categoryId: "family", sortOrder: 0),
        AmountRule(minAmount: 120_000, maxAmount: 120_000, afterEvent: .salary, windowDays: 3, categoryId: "family", sortOrder: 1),
        AmountRule(minAmount: 53_500, maxAmount: 54_500, afterEvent: .advance, windowDays: 7, categoryId: "installments", sortOrder: 2),
    ]
}

/// Первое подходящее правило по `sortOrder`; `amount` — всегда положительная сумма записи.
public func findAmountRule(
    day: CalendarDay,
    amount: Decimal,
    rules: [AmountRule],
    salaryEvents: [SalaryEvent]
) -> AmountRule? {
    let orderedRules = rules.sorted { first, second in first.sortOrder < second.sortOrder }
    return orderedRules.first { rule in
        isRuleMatching(rule, day: day, amount: amount, salaryEvents: salaryEvents)
    }
}

private func isRuleMatching(_ rule: AmountRule, day: CalendarDay, amount: Decimal, salaryEvents: [SalaryEvent]) -> Bool {
    guard (rule.minAmount...rule.maxAmount).contains(amount) else { return false }
    guard let afterEvent = rule.afterEvent else { return true }
    guard let anchor = findAnchorEvent(kind: afterEvent, onOrBefore: day, events: salaryEvents) else { return false }
    return anchor.day.daysUntil(day) <= rule.windowDays
}

/// Последнее обычное событие нужного вида не позже дня перевода; разовые поступления опорой не бывают.
private func findAnchorEvent(kind: SalaryEventKind, onOrBefore day: CalendarDay, events: [SalaryEvent]) -> SalaryEvent? {
    events
        .filter { event in event.kind == kind && !event.isOneOff && event.day <= day }
        .max { first, second in first.day < second.day }
}
