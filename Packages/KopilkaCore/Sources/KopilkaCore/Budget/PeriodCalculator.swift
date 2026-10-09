import Foundation

/// Бюджетный период: от `start` включительно до `endExclusive` не включительно.
public struct Period: Equatable, Hashable, Sendable {
    public let start: CalendarDay
    public let endExclusive: CalendarDay

    public init(start: CalendarDay, endExclusive: CalendarDay) {
        self.start = start
        self.endExclusive = endExclusive
    }

    public func contains(_ day: CalendarDay) -> Bool {
        start <= day && day < endExclusive
    }

    public var dayCount: Int {
        start.daysUntil(endExclusive)
    }

    /// Все дни периода по порядку.
    public var days: [CalendarDay] {
        (0..<dayCount).map { offset in start.adding(days: offset) }
    }
}

/// Период, в который попадает `day` (спека §5.7).
public func makePeriod(containing day: CalendarDay, mode: PeriodMode, salaryEvents: [SalaryEvent]) -> Period {
    switch mode {
    case .calendarMonth:
        return makeCalendarMonth(containing: day)
    case .salaryMonth:
        return makeSalaryPeriod(containing: day, boundaryKinds: [.salary], salaryEvents: salaryEvents)
    case .halfMonth:
        return makeSalaryPeriod(containing: day, boundaryKinds: [.advance, .salary], salaryEvents: salaryEvents)
    }
}

/// С 1-го числа месяца, в котором лежит `day`, до 1-го числа следующего.
public func makeCalendarMonth(containing day: CalendarDay) -> Period {
    let start = CalendarDay(year: day.year, month: day.month, day: 1)
    let nextMonthIndex = day.year * 12 + day.month
    let endExclusive = CalendarDay(year: nextMonthIndex / 12, month: nextMonthIndex % 12 + 1, day: 1)
    return Period(start: start, endExclusive: endExclusive)
}

/// Период между поступлениями: зарплатный месяц (только зарплата) или полмесяца (аванс и зарплата).
private func makeSalaryPeriod(containing day: CalendarDay, boundaryKinds: [SalaryEventKind], salaryEvents: [SalaryEvent]) -> Period {
    // Разовое поступление (премия) не двигает границы периода.
    let boundaryDays = salaryEvents
        .filter { event in boundaryKinds.contains(event.kind) && !event.isOneOff }
        .map { event in event.day }
        .sorted()

    let start = boundaryDays.last { boundaryDay in boundaryDay <= day } ?? makeCalendarMonth(containing: day).start
    let endExclusive = findPeriodEnd(containing: day, start: start, boundaryDays: boundaryDays, boundaryKinds: boundaryKinds, salaryEvents: salaryEvents)
    return Period(start: start, endExclusive: endExclusive)
}

/// Конец периода: фактическое следующее поступление, иначе ожидаемое (§5.4).
private func findPeriodEnd(
    containing day: CalendarDay,
    start: CalendarDay,
    boundaryDays: [CalendarDay],
    boundaryKinds: [SalaryEventKind],
    salaryEvents: [SalaryEvent]
) -> CalendarDay {
    if let nextActualDay = boundaryDays.first(where: { boundaryDay in boundaryDay > day }) {
        return nextActualDay
    }

    let predictedDays = boundaryKinds.compactMap { kind in
        predictNextEvent(kind: kind, after: start, history: salaryEvents, lookbackCount: 3)?.day
    }
    // Прогноз есть всегда, когда start — поступление; без истории start — 1-е число, и это ровно месяц.
    guard let predictedEnd = predictedDays.min() else { return makeCalendarMonth(containing: start).endExclusive }

    // Поступление опаздывает: период тянется, пока оно не придёт, иначе сегодня оказалось бы вне периода.
    return max(predictedEnd, day.adding(days: 1))
}
