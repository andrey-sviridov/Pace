import Foundation
import KopilkaCore

/// «16.07.2026» — как даты в выписке.
func formatDay(_ day: CalendarDay) -> String {
    String(format: "%02d.%02d.%04d", day.day, day.month, day.year)
}

/// «1 операция», «3 операции», «1160 операций».
func formatOperationCount(_ count: Int) -> String {
    let lastTwoDigits = count % 100
    let lastDigit = count % 10
    guard !(11...14).contains(lastTwoDigits) else { return "\(count) операций" }
    switch lastDigit {
    case 1:
        return "\(count) операция"
    case 2...4:
        return "\(count) операции"
    default:
        return "\(count) операций"
    }
}

/// «Выписка», «Apple Pay», «SMS», «Вручную».
func makeSourceKindTitle(_ kind: SourceKind) -> String {
    switch kind {
    case .statement:
        return "Выписка"
    case .applePay:
        return "Apple Pay"
    case .sms:
        return "SMS"
    case .manual:
        return "Вручную"
    }
}
