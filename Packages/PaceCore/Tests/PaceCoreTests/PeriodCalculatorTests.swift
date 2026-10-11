import Foundation
import Testing
@testable import PaceCore

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

@Suite struct PeriodEndKindTests {
    private let history = [
        makeSalaryEvent("15.08.2026", .advance, 150_000),
        makeSalaryEvent("30.08.2026", .salary),
        makeSalaryEvent("15.09.2026", .advance, 150_000),
        makeSalaryEvent("30.09.2026", .salary),
    ]

    @Test func calendarMonthHasNoEndEvent() {
        let period = makePeriod(containing: makeDay("09.10.2026"), mode: .calendarMonth, salaryEvents: history)
        #expect(findPeriodEndKind(period: period, mode: .calendarMonth, salaryEvents: history) == nil)
    }

    @Test func salaryMonthEndsWithSalary() {
        let period = makePeriod(containing: makeDay("09.10.2026"), mode: .salaryMonth, salaryEvents: history)
        #expect(findPeriodEndKind(period: period, mode: .salaryMonth, salaryEvents: history) == .salary)
    }

    @Test func firstHalfEndsWithAdvance() {
        let period = makePeriod(containing: makeDay("09.10.2026"), mode: .halfMonth, salaryEvents: history)
        #expect(period.endExclusive == makeDay("15.10.2026"))
        #expect(findPeriodEndKind(period: period, mode: .halfMonth, salaryEvents: history) == .advance)
    }

    @Test func secondHalfEndsWithSalary() {
        let events = history + [makeSalaryEvent("15.10.2026", .advance, 150_000)]
        let period = makePeriod(containing: makeDay("20.10.2026"), mode: .halfMonth, salaryEvents: events)
        #expect(findPeriodEndKind(period: period, mode: .halfMonth, salaryEvents: events) == .salary)
    }

    @Test func actualEarlyEventDecidesKind() {
        let events = history + [makeSalaryEvent("12.10.2026", .advance, 150_000)]
        let period = makePeriod(containing: makeDay("09.10.2026"), mode: .halfMonth, salaryEvents: events)
        #expect(period.endExclusive == makeDay("12.10.2026"))
        #expect(findPeriodEndKind(period: period, mode: .halfMonth, salaryEvents: events) == .advance)
    }

    @Test func noHistoryMeansMonthEnd() {
        let period = makePeriod(containing: makeDay("09.10.2026"), mode: .salaryMonth, salaryEvents: [])
        #expect(findPeriodEndKind(period: period, mode: .salaryMonth, salaryEvents: []) == nil)
    }
}
