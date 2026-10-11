import SwiftUI
import PaceCore

/// Поле ввода суммы в тенге. Пустое или нечитаемое поле даёт `nil` — экран сам решает, можно ли идти дальше.
struct MoneyField: View {
    let title: String
    @Binding var amount: Decimal?

    @Environment(\.theme) private var theme
    @State private var text = ""

    var body: some View {
        // Обычная строка формы: подпись слева, сумма справа, текст того же размера, что и в остальных строках.
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .foregroundStyle(theme.text)
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .foregroundStyle(theme.text)
                Text("₸")
                    .foregroundStyle(theme.secondaryText)
            }
            if isUnreadable {
                Text("Не похоже на сумму")
                    .font(.footnote)
                    .foregroundStyle(theme.over)
            }
        }
        .onAppear {
            text = formatAmountForEditing(amount)
        }
        .onChange(of: text) {
            amount = readTypedAmount(text)
        }
    }

    private var isUnreadable: Bool {
        !text.isEmpty && amount == nil
    }
}

/// Без разделителя тысяч: так строку проще править, и она читается обратно тем же разбором.
private func formatAmountForEditing(_ amount: Decimal?) -> String {
    guard let amount else { return "" }
    return amount.formatted(
        .number
            .grouping(.never)
            .precision(.fractionLength(0...2))
            .locale(Locale(identifier: "ru_RU"))
    )
}

/// Недописанная сумма — обычное состояние поля, а не сбой, поэтому ошибку разбора превращаем в «суммы нет».
private func readTypedAmount(_ text: String) -> Decimal? {
    guard !text.isEmpty else { return nil }
    do {
        return try parseAmount(text)
    } catch {
        return nil
    }
}
