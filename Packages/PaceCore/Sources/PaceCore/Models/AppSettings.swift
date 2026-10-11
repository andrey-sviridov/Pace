import Foundation
import SwiftData

/// В базе должна быть ровно одна запись.
@Model
public final class AppSettings {
    public var theme: ThemeName
    public var periodMode: PeriodMode
    public var employerName: String
    public var isApplePayEnabled: Bool
    public var isSmsEnabled: Bool
    public var shouldShowRemainingAfterPayment: Bool
    public var monthlySavingsGoal: Decimal
    public var hasFinishedSetup: Bool
    // Значения по умолчанию прямо в объявлении: так SwiftData сам добавит поля в уже существующую базу.
    /// Есть аванс — главная считает «до аванса» (или до зарплаты, что ближе), а месяц показывает строкой ниже.
    public var hasAdvance: Bool = true
    /// Время операции в «Проверьте новое» и журнале (оно есть только у SMS и Apple Pay).
    public var shouldShowOperationTime: Bool = true
    /// Хранится необязательным: в базах до появления режима поле пустое, а значение по умолчанию
    /// у enum SwiftData в старые записи не подставляет — чтение пустого поля роняло приложение.
    private var storedAppearance: AppearanceMode?

    public init(
        theme: ThemeName = .glow,
        periodMode: PeriodMode = .salaryMonth,
        employerName: String = "АЦЭПАК",
        isApplePayEnabled: Bool = false,
        isSmsEnabled: Bool = false,
        shouldShowRemainingAfterPayment: Bool = false,
        monthlySavingsGoal: Decimal = 0,
        hasFinishedSetup: Bool = false,
        hasAdvance: Bool = true,
        shouldShowOperationTime: Bool = true,
        appearance: AppearanceMode = .system
    ) {
        self.theme = theme
        self.periodMode = periodMode
        self.employerName = employerName
        self.isApplePayEnabled = isApplePayEnabled
        self.isSmsEnabled = isSmsEnabled
        self.shouldShowRemainingAfterPayment = shouldShowRemainingAfterPayment
        self.monthlySavingsGoal = monthlySavingsGoal
        self.hasFinishedSetup = hasFinishedSetup
        self.hasAdvance = hasAdvance
        self.shouldShowOperationTime = shouldShowOperationTime
        self.storedAppearance = appearance
    }

    /// Светлая или тёмная главная тема; по умолчанию — как в системе.
    public var appearance: AppearanceMode {
        get { storedAppearance ?? .system }
        set { storedAppearance = newValue }
    }
}
