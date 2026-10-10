import Foundation
import Testing
@testable import KopilkaCore

@Suite struct DisplayFormattingTests {
    // ru_RU разделяет тысячи неразрывным пробелом.
    private let nonBreakingSpace = "\u{00A0}"

    @Test func smallAmountStaysWhole() {
        #expect(formatThousands(800) == "800")
        #expect(formatThousands(Decimal(string: "999.4")!) == "999")
        #expect(formatThousands(0) == "0")
    }

    @Test func belowTenThousandKeepsOneDecimal() {
        #expect(formatThousands(1_500) == "1,5k")
        #expect(formatThousands(2_000) == "2k")
        #expect(formatThousands(2_049) == "2k")
        #expect(formatThousands(9_960) == "10k")
    }

    @Test func largeAmountRoundsToWholeThousands() {
        #expect(formatThousands(42_300) == "42k")
        #expect(formatThousands(186_500) == "187k")
        #expect(formatThousands(999_400) == "999k")
        #expect(formatThousands(999_600) == "1 млн")
        #expect(formatThousands(1_000_000) == "1 млн")
        #expect(formatThousands(1_234_567) == "1,2 млн")
        #expect(formatThousands(-2_500_000) == "-2,5 млн")
    }

    @Test func negativeAmountKeepsSign() {
        #expect(formatThousands(-42_300) == "-42k")
        #expect(formatThousands(-1_500) == "-1,5k")
    }

    @Test func shortDayUsesGenitiveMonth() {
        #expect(formatShortDay(makeDay("15.10.2026")) == "15 окт")
        #expect(formatShortDay(makeDay("03.05.2026")) == "3 мая")
        #expect(formatShortDay(makeDay("31.12.2026")) == "31 дек")
    }

    @Test func dayCountWords() {
        #expect(formatDayCount(1) == "1 день")
        #expect(formatDayCount(3) == "3 дня")
        #expect(formatDayCount(6) == "6 дней")
        #expect(formatDayCount(11) == "11 дней")
        #expect(formatDayCount(21) == "21 день")
        #expect(formatDayCount(24) == "24 дня")
        #expect(formatDayCount(112) == "112 дней")
    }

    @Test func calendarDayUsesGivenTimeZone() {
        // 2026-10-09 20:00 UTC — в Алматы (UTC+5) уже 10 октября.
        let date = Date(timeIntervalSince1970: 1_791_576_000)
        var almatyCalendar = Calendar(identifier: .gregorian)
        almatyCalendar.timeZone = TimeZone(identifier: "Asia/Almaty")!
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = .gmt

        #expect(makeCalendarDay(date: date, calendar: utcCalendar) == makeDay("09.10.2026"))
        #expect(makeCalendarDay(date: date, calendar: almatyCalendar) == makeDay("10.10.2026"))
    }

    @Test func dateFromCalendarDayRoundTripsInSameCalendar() {
        var almatyCalendar = Calendar(identifier: .gregorian)
        almatyCalendar.timeZone = TimeZone(identifier: "Asia/Almaty")!
        let day = makeDay("01.03.2026")

        let date = makeDate(day: day, calendar: almatyCalendar)

        #expect(makeCalendarDay(date: date, calendar: almatyCalendar) == day)
    }
}

@Suite struct RoundDownTests {
    @Test func dropsKopecksDownward() {
        #expect(roundDownToWholeTenge(Decimal(string: "288610.92")!) == 288_610)
        #expect(roundDownToWholeTenge(500) == 500)
    }
}

@Suite struct TengeFormattingTests {
    @Test func showsKopecksOnlyWhenPresent() {
        #expect(formatTenge(1_234_567) == "1\u{00A0}234\u{00A0}567 ₸")
        #expect(formatTenge(Decimal(string: "6933.41")!) == "6\u{00A0}933,41 ₸")
        #expect(formatTenge(Decimal(string: "10.5")!) == "10,50 ₸")
    }

    @Test func roundsOverspendUp() {
        #expect(roundUpToWholeTenge(Decimal(string: "5000.30")!) == 5_001)
        #expect(roundUpToWholeTenge(5_000) == 5_000)
    }
}
