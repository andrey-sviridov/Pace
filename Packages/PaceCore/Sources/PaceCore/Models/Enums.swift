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

/// Темы «Графит» и «Свечение».
public enum ThemeName: String, Codable, Sendable {
    case graphite, glow

    /// Прежние темы (light, dark, paper) убраны: их значения из базы и резервных копий читаются как «Графит».
    public init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = ThemeName(rawValue: rawValue) ?? .graphite
    }
}
