import SwiftUI

/// Сумма в тенге: «6 933,41 ₸». Цифры одной ширины, чтобы суммы в столбик не прыгали.
struct MoneyText: View {
    let amount: Decimal
    var style: MoneyTextStyle = .body

    @Environment(\.theme) private var theme

    var body: some View {
        Text(formatTenge(amount))
            .font(makeFont(style: style, theme: theme))
            .monospacedDigit()
            .foregroundStyle(theme.text)
    }
}

/// hero — главная цифра экрана (шрифт темы), title — остатки на карточках, body — суммы в строках.
enum MoneyTextStyle {
    case hero, title, body
}

private func makeFont(style: MoneyTextStyle, theme: Theme) -> Font {
    switch style {
    case .hero:
        return theme.heroFont
    case .title:
        return .title3.weight(.semibold)
    case .body:
        return .body
    }
}
