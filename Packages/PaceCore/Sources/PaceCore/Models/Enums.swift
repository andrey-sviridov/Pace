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

/// Темы A / B / C / D из дизайна.
public enum ThemeName: String, Codable, Sendable {
    case light, dark, paper, graphite
}
