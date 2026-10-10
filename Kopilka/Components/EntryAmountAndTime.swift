import SwiftUI
import KopilkaCore

/// Сумма со знаком и под ней время операции. Время есть только у SMS и Apple Pay (в выписке его нет),
/// и показывается, если включено в настройках.
struct EntryAmountAndTime: View {
    let entry: JournalEntry
    let isTimeShown: Bool
    let theme: Theme

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            EntryAmountText(amount: entry.amount, type: entry.type)
            if isTimeShown, let time = entry.time {
                Text(formatOperationTime(time, calendar: .current))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }
}
