import Foundation

/// Дата операции без времени и часового пояса.
public struct CalendarDay: Hashable, Comparable, Codable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Разбирает "13.10.2025"; несуществующая дата даёт nil.
    public init?(dotted: String) {
        let parts = dotted.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let day = Int(parts[0]),
              let month = Int(parts[1]),
              let year = Int(parts[2])
        else { return nil }

        let candidate = CalendarDay(year: year, month: month, day: day)
        // Календарь сам нормализует 32.13, поэтому сверяем компоненты обратно.
        guard let date = Self.calendar.date(from: candidate.dateComponents),
              CalendarDay(date: date) == candidate
        else { return nil }
        self = candidate
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public func adding(days: Int) -> CalendarDay {
        guard let date = Self.calendar.date(from: dateComponents),
              let shiftedDate = Self.calendar.date(byAdding: .day, value: days, to: date)
        else { return self }
        return CalendarDay(date: shiftedDate)
    }

    public func daysUntil(_ other: CalendarDay) -> Int {
        guard let startDate = Self.calendar.date(from: dateComponents),
              let endDate = Self.calendar.date(from: other.dateComponents)
        else { return 0 }
        return Self.calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
    }

    // Григорианский календарь в UTC: нужна только арифметика дней, без переходов на летнее время.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private var dateComponents: DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    private init(date: Date) {
        let components = Self.calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 0, month: components.month ?? 0, day: components.day ?? 0)
    }
}
