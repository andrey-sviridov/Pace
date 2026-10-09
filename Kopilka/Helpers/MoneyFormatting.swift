import Foundation

/// «1 234 567 ₸» или «6 933,41 ₸»: копейки показываем, только если они есть, и тогда всегда двумя цифрами.
func formatTenge(_ amount: Decimal) -> String {
    let fractionDigits = isWholeNumber(amount) ? 0 : 2
    let number = amount.formatted(
        .number
            .precision(.fractionLength(fractionDigits))
            .locale(Locale(identifier: "ru_RU"))
    )
    return "\(number) ₸"
}

private func isWholeNumber(_ amount: Decimal) -> Bool {
    var value = amount
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, 0, .plain)
    return rounded == amount
}
