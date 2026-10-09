import Foundation

/// Ключ продавца: верхний регистр, без разделителей, хвостов касс/филиалов и цифр.
public func makeMerchantKey(_ merchant: String) -> String {
    let lettersAndDigits = merchant.uppercased().filter { character in character.isLetter || character.isNumber }
    // Хвосты вырезаем до удаления цифр: по ним (ASF36, KASSA1) мы их и узнаём.
    let withoutTails = lettersAndDigits.replacingOccurrences(
        of: "(SHOPKASSA|KASSA)[0-9]*|(ASF|NSF|NF)[0-9]+",
        with: "",
        options: .regularExpression
    )
    return withoutTails.filter { character in !character.isNumber }
}

/// Читаемое название для записи: `"MAGNUM.ASF36."` → `"Magnum"`.
public func makeTitle(merchant: String) -> String {
    let separators = CharacterSet(charactersIn: ".*_-")
    let spaced = merchant.uppercased().components(separatedBy: separators).joined(separator: " ")
    let withoutTails = spaced.replacingOccurrences(
        of: "\\b((SHOPKASSA|KASSA|ASF|NSF|NF)[0-9]*|[0-9]+)\\b",
        with: " ",
        options: .regularExpression
    )
    let words = withoutTails.split(whereSeparator: { character in character.isWhitespace })
    guard !words.isEmpty else { return merchant.trimmingCharacters(in: .whitespaces) }

    return words.joined(separator: " ").capitalized
}
