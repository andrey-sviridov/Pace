import Foundation
import SwiftData

/// В базе должна быть ровно одна запись.
@Model
public final class AppSettings {
    public var theme: ThemeName
    public var periodMode: PeriodMode
    public var employerName: String
    public var kaspiOwnCardUntil: CalendarDay
    public var isApplePayEnabled: Bool
    public var isSmsEnabled: Bool
    public var shouldShowRemainingAfterPayment: Bool
    public var monthlySavingsGoal: Decimal
    public var hasFinishedSetup: Bool

    public init(
        theme: ThemeName = .light,
        periodMode: PeriodMode = .salaryMonth,
        employerName: String = "АЦЭПАК",
        kaspiOwnCardUntil: CalendarDay = CalendarDay(year: 2026, month: 3, day: 1),
        isApplePayEnabled: Bool = false,
        isSmsEnabled: Bool = false,
        shouldShowRemainingAfterPayment: Bool = false,
        monthlySavingsGoal: Decimal = 0,
        hasFinishedSetup: Bool = false
    ) {
        self.theme = theme
        self.periodMode = periodMode
        self.employerName = employerName
        self.kaspiOwnCardUntil = kaspiOwnCardUntil
        self.isApplePayEnabled = isApplePayEnabled
        self.isSmsEnabled = isSmsEnabled
        self.shouldShowRemainingAfterPayment = shouldShowRemainingAfterPayment
        self.monthlySavingsGoal = monthlySavingsGoal
        self.hasFinishedSetup = hasFinishedSetup
    }
}
