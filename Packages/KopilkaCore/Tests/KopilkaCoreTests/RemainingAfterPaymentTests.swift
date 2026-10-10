import Foundation
import Testing
@testable import KopilkaCore

@Suite struct RemainingAfterPaymentTests {
    private func makeStatus(spent: Decimal, limit: Decimal, level: LimitLevel) -> LimitStatus {
        let category = SpendingCategory(id: "cafes", name: "Кафе и кофе", iconName: "cup.and.saucer", kind: .flexible)
        return LimitStatus(category: category, limit: limit, spent: spent, usedShare: 0, paceShare: 0, level: level)
    }

    @Test func warningShowsWhatIsLeft() {
        let statuses = [makeStatus(spent: 25_800, limit: 30_000, level: .warning)]

        let text = makeRemainingAfterPaymentText(categoryId: "cafes", statuses: statuses)

        #expect(text == "Кафе и кофе: осталось 4\u{00A0}200 ₸ из 30\u{00A0}000 ₸")
    }

    @Test func overShowsHowMuchAbove() {
        let statuses = [makeStatus(spent: 32_000, limit: 30_000, level: .over)]

        let text = makeRemainingAfterPaymentText(categoryId: "cafes", statuses: statuses)

        #expect(text == "Кафе и кофе: перерасход 2\u{00A0}000 ₸ сверх 30\u{00A0}000 ₸")
    }

    @Test func normalOrNoLimitShowsNothing() {
        let statuses = [makeStatus(spent: 5_000, limit: 30_000, level: .normal)]

        #expect(makeRemainingAfterPaymentText(categoryId: "cafes", statuses: statuses) == nil)
        #expect(makeRemainingAfterPaymentText(categoryId: "groceries", statuses: statuses) == nil)
        #expect(makeRemainingAfterPaymentText(categoryId: nil, statuses: statuses) == nil)
    }
}

@Suite struct UnparsedRealtimeEntryTests {
    @Test func foreignCurrencyApplePayBecomesPlaceholderForReview() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let entry = makeUnparsedRealtimeEntry(kind: .applePay, title: "Оплата в USD — проверьте", text: "AMAZON · 10.0 USD", now: now, calendar: Calendar(identifier: .gregorian))

        #expect(entry.type == .adjustment)
        #expect(entry.amount == 0)
        #expect(!entry.affectsBalance)
        #expect(!entry.isReviewed)
        #expect(entry.title == "Оплата в USD — проверьте")
        #expect(entry.sources.map { source in source.kind } == [.applePay])
    }
}
