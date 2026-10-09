import Foundation
import Testing
@testable import KopilkaCore

struct CalendarDayTests {
    @Test func parsesDottedDate() {
        #expect(CalendarDay(dotted: "13.10.2025") == CalendarDay(year: 2025, month: 10, day: 13))
    }

    @Test func rejectsImpossibleDate() {
        #expect(CalendarDay(dotted: "32.13.2025") == nil)
    }

    @Test func addsDaysAcrossMonthEnd() {
        let day = CalendarDay(year: 2025, month: 1, day: 31)
        #expect(day.adding(days: 1) == CalendarDay(year: 2025, month: 2, day: 1))
    }

    @Test func addsDaysAcrossYearEnd() {
        let day = CalendarDay(year: 2025, month: 12, day: 31)
        #expect(day.adding(days: 1) == CalendarDay(year: 2026, month: 1, day: 1))
    }

    @Test func subtractsDays() {
        let day = CalendarDay(year: 2026, month: 1, day: 1)
        #expect(day.adding(days: -1) == CalendarDay(year: 2025, month: 12, day: 31))
    }

    @Test func countsDaysUntil() {
        let start = CalendarDay(year: 2025, month: 12, day: 30)
        let end = CalendarDay(year: 2026, month: 1, day: 2)
        #expect(start.daysUntil(end) == 3)
        #expect(end.daysUntil(start) == -3)
    }

    @Test func comparesChronologically() {
        #expect(CalendarDay(year: 2025, month: 12, day: 31) < CalendarDay(year: 2026, month: 1, day: 1))
    }

    @Test func roundTripsThroughCodable() throws {
        let day = CalendarDay(year: 2025, month: 10, day: 13)
        let data = try JSONEncoder().encode(day)
        #expect(try JSONDecoder().decode(CalendarDay.self, from: data) == day)
    }
}
