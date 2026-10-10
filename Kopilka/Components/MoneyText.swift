import SwiftUI

/// Сумма в тенге: «6 933,41 ₸». Цифры одной ширины, чтобы суммы в столбик не прыгали.
struct MoneyText: View {
    let amount: Decimal
    var font: Font = .body

    @Environment(\.theme) private var theme

    var body: some View {
        Text(formatTenge(amount))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(theme.text)
    }
}
