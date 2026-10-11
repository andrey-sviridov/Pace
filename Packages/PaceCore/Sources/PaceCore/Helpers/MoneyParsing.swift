import Foundation

public enum ParsingError: Error, Equatable {
    case badAmount(String)
    case badDate(String)
}

/// Разбирает сумму из выписки: "-1 093,00" -> -1093.
public func parseAmount(_ text: String) throws -> Decimal {
    // Банк разделяет тысячи обычным и неразрывным пробелом, дробную часть — запятой.
    let cleanedText = text
        .replacingOccurrences(of: "\u{00A0}", with: "")
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: ",", with: ".")
    // Decimal(string:) молча берёт префикс ("12abc" -> 12), поэтому формат проверяем целиком.
    guard cleanedText.range(of: #"^[+-]?\d+(\.\d+)?$"#, options: .regularExpression) != nil else {
        throw ParsingError.badAmount(text)
    }
    // Локаль POSIX, чтобы точка всегда была десятичным разделителем.
    guard let amount = Decimal(string: cleanedText, locale: Locale(identifier: "en_US_POSIX")) else {
        throw ParsingError.badAmount(text)
    }
    return amount
}
