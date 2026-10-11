import SwiftUI
import PaceCore

/// Сумма записи со знаком: расход «−», доход «+» цветом акцента, перемещение без знака.
struct EntryAmountText: View {
    let amount: Decimal
    let type: EntryType

    @Environment(\.theme) private var theme

    var body: some View {
        Text(formatSignedTenge(amount, type: type))
            .monospacedDigit()
            .foregroundStyle(type == .income ? theme.accent : theme.text)
    }
}
