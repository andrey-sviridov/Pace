import Foundation

// Короткие подписи для экранов: «42k», «15 окт», «6 дней». Без SwiftUI, чтобы их можно было проверить тестами.

/// Сегодняшний день пользователя: календарь передаётся снаружи, чтобы часовой пояс был виден по вызову.
public func makeCalendarDay(date: Date, calendar: Calendar) -> CalendarDay {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    guard let year = components.year, let month = components.month, let day = components.day else {
        preconditionFailure("Calendar обязан вернуть год, месяц и день")
    }
    return CalendarDay(year: year, month: month, day: day)
}

/// Начало дня в календаре пользователя — для системного выбора даты (DatePicker работает с Date).
public func makeDate(day: CalendarDay, calendar: Calendar) -> Date {
    let components = DateComponents(year: day.year, month: day.month, day: day.day)
    guard let date = calendar.date(from: components) else {
        preconditionFailure("CalendarDay всегда настоящая дата, Calendar обязан её построить")
    }
    return date
}

/// «1 234 567 ₸» или «6 933,41 ₸»: копейки показываем, только если они есть, и тогда всегда двумя цифрами.
public func formatTenge(_ amount: Decimal) -> String {
    let fractionDigits = roundAmount(amount, fractionDigits: 0) == amount ? 0 : 2
    let number = amount.formatted(
        .number
            .precision(.fractionLength(fractionDigits))
            .locale(Locale(identifier: "ru_RU"))
    )
    return "\(number) ₸"
}

/// Сумма в тысячах для легенд и лимитов: «800», «1,5k», «42k»; от миллиона — «1 млн», «1,2 млн».
public func formatThousands(_ amount: Decimal) -> String {
    // Сравниваем уже округлённые тысячи: 999 600 иначе превратилось бы в «1 000k».
    guard abs(roundAmount(amount / 1000, fractionDigits: 0)) < 1000 else {
        let millions = roundAmount(amount / 1_000_000, fractionDigits: 1)
        return formatRussianNumber(millions, maxFractionDigits: 1) + " млн"
    }
    guard abs(amount) >= 1000 else {
        return formatRussianNumber(roundAmount(amount, fractionDigits: 0), maxFractionDigits: 0)
    }
    // До 10 тысяч десятые ещё заметны (1,5k против 2k), дальше они только шумят.
    let fractionDigits = abs(amount) < 10_000 ? 1 : 0
    let thousands = roundAmount(amount / 1000, fractionDigits: fractionDigits)
    return formatRussianNumber(thousands, maxFractionDigits: fractionDigits) + "k"
}

/// «15 окт». Месяцы в родительном падеже, без точки: «3 мая», а не «3 май.».
public func formatShortDay(_ day: CalendarDay) -> String {
    let monthNames = ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]
    return "\(day.day) \(monthNames[day.month - 1])"
}

/// Подпись столбика периода: календарный месяц — «сен», зарплатный — день начала «10 сен».
public func formatPeriodLabel(_ period: Period) -> String {
    let isCalendarMonth = period == makeCalendarMonth(containing: period.start)
    guard isCalendarMonth else { return formatShortDay(period.start) }
    let monthNames = ["янв", "фев", "мар", "апр", "май", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]
    return monthNames[period.start.month - 1]
}

/// «1 день», «3 дня», «11 дней».
public func formatDayCount(_ count: Int) -> String {
    "\(count) \(choosePluralForm(count: count, one: "день", few: "дня", many: "дней"))"
}

/// Русское множественное число: 1 и 21 — one, 2–4 и 22–24 — few, остальное и 11–14 — many.
public func choosePluralForm(count: Int, one: String, few: String, many: String) -> String {
    let lastTwoDigits = abs(count) % 100
    let lastDigit = abs(count) % 10
    guard !(11...14).contains(lastTwoDigits) else { return many }
    switch lastDigit {
    case 1:
        return one
    case 2...4:
        return few
    default:
        return many
    }
}

private func roundAmount(_ amount: Decimal, fractionDigits: Int) -> Decimal {
    var source = amount
    var rounded = Decimal()
    NSDecimalRound(&rounded, &source, fractionDigits, .plain)
    return rounded
}

private func formatRussianNumber(_ number: Decimal, maxFractionDigits: Int) -> String {
    number.formatted(
        .number
            .precision(.fractionLength(0...maxFractionDigits))
            .locale(Locale(identifier: "ru_RU"))
    )
}
