import Foundation

/// Дата операции без времени и часового пояса. Всегда настоящая дата календаря.
public struct CalendarDay: Hashable, Comparable, Codable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        // Calendar молча превращает месяц 13 в январь следующего года, поэтому ловим мусор на входе.
        precondition(Self.isRealDate(year: year, month: month, day: day), "Несуществующая дата \(day).\(month).\(year)")
        self.year = year
        self.month = month
        self.day = day
    }

    /// Разбирает строго "dd.MM.yyyy"; несуществующая дата или другой формат дают nil.
    public init?(dotted: String) {
        let parts = dotted.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 2, parts[1].count == 2, parts[2].count == 4,
              parts.allSatisfy({ part in part.allSatisfy { character in character.isASCII && character.isNumber } }),
              let day = Int(parts[0]),
              let month = Int(parts[1]),
              let year = Int(parts[2]),
              Self.isRealDate(year: year, month: month, day: day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    // Свой Decodable, чтобы из базы или JSON не вошла невозможная дата.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let year = try container.decode(Int.self, forKey: .year)
        let month = try container.decode(Int.self, forKey: .month)
        let day = try container.decode(Int.self, forKey: .day)
        guard Self.isRealDate(year: year, month: month, day: day) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Несуществующая дата \(day).\(month).\(year)")
            )
        }
        self.init(year: year, month: month, day: day)
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public func adding(days: Int) -> CalendarDay {
        guard let date = Self.calendar.date(from: dateComponents),
              let shiftedDate = Self.calendar.date(byAdding: .day, value: days, to: date)
        else { preconditionFailure("Дата валидна по построению, Calendar обязан её посчитать") }
        return CalendarDay(date: shiftedDate)
    }

    public func daysUntil(_ other: CalendarDay) -> Int {
        guard let startDate = Self.calendar.date(from: dateComponents),
              let endDate = Self.calendar.date(from: other.dateComponents),
              let dayCount = Self.calendar.dateComponents([.day], from: startDate, to: endDate).day
        else { preconditionFailure("Даты валидны по построению, Calendar обязан посчитать разницу") }
        return dayCount
    }

    private enum CodingKeys: String, CodingKey {
        case year, month, day
    }

    // Григорианский календарь в GMT: нужна только арифметика дней, без переходов на летнее время.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    // Календарь нормализует 32.13 в соседнюю дату, поэтому сверяем компоненты обратно.
    private static func isRealDate(year: Int, month: Int, day: Int) -> Bool {
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else { return false }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        return roundTrip.year == year && roundTrip.month == month && roundTrip.day == day
    }

    private var dateComponents: DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    private init(date: Date) {
        let components = Self.calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            preconditionFailure("Calendar обязан вернуть год, месяц и день")
        }
        self.init(year: year, month: month, day: day)
    }
}
