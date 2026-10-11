import Foundation
import Testing
@testable import PaceCore

@Suite struct SmsParserTests {
    @Test func parsesPurchaseWithMerchantAndBalance() {
        let parsed = parseSms("Покупка 1 500,00 KZT MAGNUM Остаток 85 430,00")

        #expect(parsed?.amount == 1500)
        #expect(parsed?.isIncome == false)
        #expect(parsed?.merchant == "MAGNUM")
        #expect(parsed?.balance == 85_430)
    }

    @Test func parsesIncomeWithoutMerchant() {
        let parsed = parseSms("Зачисление 402 487,00 KZT")

        #expect(parsed?.amount == 402_487)
        #expect(parsed?.isIncome == true)
        #expect(parsed?.merchant == nil)
        #expect(parsed?.balance == nil)
    }

    @Test func parsesTengeSignAndMerchantAfterPreposition() {
        let parsed = parseSms("Оплата 1500 ₸ в Yandex Go. Баланс: 12 000.50")

        #expect(parsed?.amount == 1500)
        #expect(parsed?.merchant == "Yandex Go")
        #expect(parsed?.balance == Decimal(string: "12000.5"))
    }

    @Test func parsesDotDecimalAndAtMerchant() {
        let parsed = parseSms("Purchase 1500.00 KZT at GLOVO")

        #expect(parsed?.amount == 1500)
        #expect(parsed?.merchant == "GLOVO")
    }

    @Test func incomeWithBalanceHasNoMerchant() {
        let parsed = parseSms("Зачисление 402 487,00 KZT Остаток 450 000,00")

        #expect(parsed?.merchant == nil)
        #expect(parsed?.balance == 450_000)
    }

    @Test func amountIgnoresDigitsGluedToTheLeft() {
        #expect(parseSms("Карта 1234 500 KZT")?.amount == 500)
    }

    @Test func returnsNilWithoutAmount() {
        #expect(parseSms("Ваш код подтверждения 4821") == nil)
        #expect(parseSms("") == nil)
    }

    @Test func unparsedEntryIsHarmlessPlaceholder() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt

        let entry = makeUnparsedSmsEntry(text: "что-то странное", now: now, calendar: calendar)

        #expect(entry.type == .adjustment)
        #expect(entry.amount == 0)
        #expect(entry.affectsBalance == false)
        #expect(entry.isReviewed == false)
        #expect(entry.categoryId == nil)
        #expect(entry.note == "что-то странное")
        #expect(entry.sources.count == 1)
        #expect(entry.sources.first?.kind == .sms)
        #expect(entry.sources.first?.rawText == "что-то странное")
        #expect(entry.day == CalendarDay(dotted: "15.01.2027"))
    }
}
