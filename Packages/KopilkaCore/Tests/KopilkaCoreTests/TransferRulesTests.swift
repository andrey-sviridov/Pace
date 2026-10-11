import Foundation
import Testing
@testable import KopilkaCore

@Suite struct TransferRulesTests {
    private let rules = makeDefaultAmountRules()

    private func makeEvent(_ dotted: String, _ kind: SalaryEventKind, isOneOff: Bool = false) -> SalaryEvent {
        SalaryEvent(day: CalendarDay(dotted: dotted)!, amount: 400_000, kind: kind, isOneOff: isOneOff)
    }

    private func findRule(_ dotted: String, _ amountTenge: Decimal, events: [SalaryEvent]) -> AmountRule? {
        findAmountRule(day: CalendarDay(dotted: dotted)!, amount: amountTenge, rules: rules, salaryEvents: events)
    }

    @Test func installmentOnAdvanceDay() {
        let rule = findRule("15.07.2026", 54_000, events: [makeEvent("15.07.2026", .advance)])
        #expect(rule?.categoryId == "installments")
    }

    @Test func installmentWithinWeekOfEarlyOrLateAdvance() {
        #expect(findRule("19.07.2026", 53_800, events: [makeEvent("13.07.2026", .advance)])?.categoryId == "installments")
        #expect(findRule("19.07.2026", 53_800, events: [makeEvent("17.07.2026", .advance)])?.categoryId == "installments")
    }

    @Test func familyOnSalaryDay() {
        let rule = findRule("29.05.2026", 100_000, events: [makeEvent("29.05.2026", .salary)])
        #expect(rule?.categoryId == "family")
    }

    @Test func familyWindowIsThreeDays() {
        let events = [makeEvent("29.05.2026", .salary)]
        #expect(findRule("01.06.2026", 120_000, events: events)?.categoryId == "family")
        #expect(findRule("02.06.2026", 120_000, events: events) == nil)
    }

    /// Правила по дате больше нет: старый перевод без зарплаты рядом ни под что не подходит.
    @Test func oldTransferWithoutSalaryMatchesNothing() {
        #expect(findRule("31.10.2025", 400_000, events: []) == nil)
        #expect(findRule("28.02.2026", 100_000, events: []) == nil)
    }

    @Test func noRuleMatches() {
        #expect(findRule("22.08.2026", 10_000, events: [makeEvent("15.08.2026", .advance)]) == nil)
    }

    @Test func oneOffEventIsNotAnAnchor() {
        let events = [makeEvent("29.05.2026", .salary, isOneOff: true)]
        #expect(findRule("29.05.2026", 100_000, events: events) == nil)
    }

    @Test func anchorIsNotInTheFuture() {
        #expect(findRule("10.07.2026", 54_000, events: [makeEvent("15.07.2026", .advance)]) == nil)
    }

    @Test func staleAdvanceDoesNotAnchorTransfer() {
        #expect(findRule("01.08.2026", 54_000, events: [makeEvent("15.07.2026", .advance)]) == nil)
    }

    @Test func staleSalaryDoesNotAnchorTransfer() {
        #expect(findRule("20.06.2026", 100_000, events: [makeEvent("29.05.2026", .salary)]) == nil)
    }

    @Test func latestAnchorWins() {
        let events = [makeEvent("15.06.2026", .advance), makeEvent("15.07.2026", .advance)]
        #expect(findRule("19.07.2026", 54_000, events: events)?.categoryId == "installments")
    }

    @Test func rulesAreResolvedBySortOrderNotArrayOrder() {
        let ownCardRule = AmountRule(minAmount: 90_000, maxAmount: 110_000, targetAccountKind: .ownOtherCard, sortOrder: -1)
        let shuffledRules = Array(rules.reversed()) + [ownCardRule]
        let events = [makeEvent("29.12.2025", .salary)]
        let rule = findAmountRule(day: CalendarDay(dotted: "29.12.2025")!, amount: 100_000, rules: shuffledRules, salaryEvents: events)
        #expect(rule?.targetAccountKind == .ownOtherCard)
    }
}
