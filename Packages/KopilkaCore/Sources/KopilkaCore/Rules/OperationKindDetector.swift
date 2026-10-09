import Foundation

public enum OperationKind: Equatable, Sendable {
    case purchase(merchant: String)
    case salary(employer: String)
    case transferToOtherCard
    case toDeposit
    case fromDeposit
    case incomingTransfer
    case refund(merchant: String)
    case loanPayment
    case mortgagePayment
    case internationalTransfer
    case monthlyFee
    case depositInterest
    case unknown
}

/// Тип операции по описанию из выписки (спека §2). Сравнение без пробелов и регистра,
/// а название продавца берём из исходного текста, чтобы в нём остались пробелы.
public func detectOperationKind(description: String) -> OperationKind {
    let normalized = normalizeDescription(description)

    // Порядок важен: проценты и ипотека маскируются под другие типы.
    if normalized.contains("ВОЗНАГРАЖД") || normalized.contains("КАПИТАЛИЗ") { return .depositInterest }
    if normalized.contains("ЖИЛСТРОЙСБЕРБАНК") { return .mortgagePayment }

    let purchasePrefix = "ОПЕРАЦИЯОПЛАТЫУКОММЕРСАНТА"
    if normalized.hasPrefix(purchasePrefix) {
        return .purchase(merchant: getTextAfterPrefix(of: description, prefix: purchasePrefix))
    }
    let salaryPrefix = "ПОСТУПЛЕНИЕНАСЧЕТТОО"
    if normalized.hasPrefix(salaryPrefix) {
        let employerText = getTextAfterPrefix(of: description, prefix: salaryPrefix)
        return .salary(employer: employerText.trimmingCharacters(in: CharacterSet(charactersIn: "\"«»“” ")))
    }
    let refundPrefix = "ПОСТУПЛЕНИЕНАКАРТУ"
    if normalized.hasPrefix(refundPrefix) {
        return .refund(merchant: getTextAfterPrefix(of: description, prefix: refundPrefix))
    }

    if normalized.hasPrefix("ПЕРЕВОДНАДРУГУЮКАРТУ") { return .transferToOtherCard }
    if normalized.hasPrefix("ПЕРЕВОДНАДЕПОЗИТ") { return .toDeposit }
    if normalized.hasPrefix("ЗАЧИСЛЕНИЕСДЕПОЗИТА") { return .fromDeposit }
    if normalized.hasPrefix("ПОСТУПЛЕНИЕПЕРЕВОДА") { return .incomingTransfer }
    if normalized.hasPrefix("ПЛАТЕЖСТЕКУЩЕГОСЧЕТА") && normalized.contains("БЕЗВОЗМЕЗДН") { return .incomingTransfer }
    if normalized.hasPrefix("ПОГАШЕНИЕБАНКОВСКОЙ") || normalized.hasPrefix("ПЕРЕВОДНАКРЕДИТRS") { return .loanPayment }
    if normalized.hasPrefix("ИСХОДЯЩИЙМЕЖДУНАРОДНЫЙПЕРЕВОД") { return .internationalTransfer }
    if normalized.hasPrefix("ЕЖЕМЕСЯЧНАЯКОМИССИЯ") { return .monthlyFee }

    return .unknown
}

/// Текст после префикса, который задан в нормализованном виде (без пробелов).
private func getTextAfterPrefix(of description: String, prefix normalizedPrefix: String) -> String {
    var remainingPrefixLength = normalizedPrefix.count
    var restStart = description.startIndex

    while remainingPrefixLength > 0 && restStart < description.endIndex {
        if !description[restStart].isWhitespace { remainingPrefixLength -= 1 }
        restStart = description.index(after: restStart)
    }
    return description[restStart...].trimmingCharacters(in: .whitespacesAndNewlines)
}
