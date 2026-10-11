import Foundation

public enum EntryType: String, Codable, Sendable {
    case expense, income, transfer, adjustment
}

public enum SourceKind: String, Codable, Sendable {
    case statement, applePay, sms, manual
}

public enum AccountKind: String, Codable, Sendable {
    case card, deposit, ownOtherCard
}

public enum CategoryKind: String, Codable, Sendable {
    case obligatory, flexible, income, transfer
}

public enum PeriodMode: String, Codable, Sendable {
    case calendarMonth, salaryMonth, halfMonth
}

/// Главная тема. Пока одна — «Свечение»; светлая или тёмная она — решает `AppearanceMode`.
public enum ThemeName: String, Codable, Sendable {
    case glow

    /// Прежние темы (light, dark, paper, graphite) убраны: их значения из базы и резервных копий читаются как «Свечение».
    public init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = ThemeName(rawValue: rawValue) ?? .glow
    }
}

/// Режим главной темы: как в системе, всегда светлая или всегда тёмная.
public enum AppearanceMode: String, Codable, Sendable {
    case system, light, dark
}
