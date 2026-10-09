import Foundation
import Testing
@testable import KopilkaCore

@Suite struct PeriodCalculatorTests {
    @Test func calendarMonthIsFirstToFirst() {
        let period = makePeriod(containing: makeDay("09.10.2026"), mode: .calendarMonth, salaryEvents: [])
        #expect(period == Period(start: makeDay("01.10.2026"), endExclusive: makeDay("01.11.2026")))
        #expect(period.dayCount == 31)
    }

    @Test func calendarMonthCrossesYear() {
        let period = makePeriod(containing: makeDay("31.12.2026"), mode: .calendarMonth, salaryEvents: [])
        #expect(period == Period(start: makeDay("01.12.2026"), endExclusive: makeDay("01.01.2027")))
    }

    @Test func salaryMonthStartsAtSalaryAndEndsAtPredictedSalary() {
        let events = [makeSalaryEvent("15.09.2026", .advance), makeSalaryEvent("30.09.2026", .salary)]
        let period = makePeriod(containing: makeDay("09.10.2026"), mode: .salaryMonth, salaryEvents: events)
        #expect(period == Period(start: makeDay("30.09.2026"), endExclusive: makeDay("30.10.2026")))
    }

    @Test func salaryMonthEndsAtActualSalaryWhenItCameEarly() {
        let events = [makeSalaryEvent("30.09.2026", .salary), makeSalaryEvent("28.10.2026", .salary)]
        let period = makePeriod(containing: makeDay("09.10.2026"), mode: .salaryMonth, salaryEvents: events)
        #expect(period == Period(start: makeDay("30.09.2026"), endExclusive: makeDay("28.10.2026")))
    }

    @Test func salaryMonthStretchesWhileSalaryIsLate() {
        let events = [makeSalaryEvent("30.09.2026", .salary)]
        let period = makePeriod(containing: makeDay("01.11.2026"), mode: .salaryMonth, salaryEvents: events)
        #expect(period == Period(start: makeDay("30.09.2026"), endExclusive: makeDay("02.11.2026")))
        #expect(period.contains(makeDay("01.11.2026")))
    }

    @Test func salaryMonthIgnoresOneOffIncome() {
        let events = [makeSalaryEvent("30.09.2026", .salary), makeSalaryEvent("05.10.2026", .salary, 1_200_000, isOneOff: true)]
        let period = makePeriod(containing: makeDay("09.10.2026"), mode: .salaryMonth, salaryEvents: events)
        #expect(period.start == makeDay("30.09.2026"))
    }

    @Test func salaryMonthWithoutHistoryFallsBackToCalendarMonth() {
        let period = makePeriod(containing: makeDay("09.10.2026"), mode: .salaryMonth, salaryEvents: [])
        #expect(period == Period(start: makeDay("01.10.2026"), endExclusive: makeDay("01.11.2026")))
    }

    @Test func halfMonthIsAdvanceToSalary() {
        let events = [makeSalaryEvent("15.09.2026", .advance), makeSalaryEvent("30.09.2026", .salary)]
        let period = makePeriod(containing: makeDay("20.09.2026"), mode: .halfMonth, salaryEvents: events)
        #expect(period == Period(start: makeDay("15.09.2026"), endExclusive: makeDay("30.09.2026")))
    }

    @Test func halfMonthAfterSalaryEndsAtPredictedAdvance() {
        let events = [makeSalaryEvent("15.09.2026", .advance), makeSalaryEvent("30.09.2026", .salary)]
        let period = makePeriod(containing: makeDay("09.10.2026"), mode: .halfMonth, salaryEvents: events)
        #expect(period == Period(start: makeDay("30.09.2026"), endExclusive: makeDay("15.10.2026")))
    }

    @Test func containsIsHalfOpen() {
        let period = makeOctober2026()
        #expect(period.contains(makeDay("01.10.2026")))
        #expect(period.contains(makeDay("31.10.2026")))
        #expect(!period.contains(makeDay("01.11.2026")))
        #expect(!period.contains(makeDay("30.09.2026")))
    }
}
