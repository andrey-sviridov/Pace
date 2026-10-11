import SwiftUI
import SwiftData
import PaceCore

/// «Сверить остаток» (спека §5.9): ввели, что показывает Homebank, — разница записывается корректировкой.
/// Плюс по депозиту — «Проценты по депозиту». В траты и лимиты корректировка не идёт.
struct ReconcileScreen: View {
    let account: Account
    let today: CalendarDay

    @Environment(AccountStore.self) private var accountStore
    @Environment(ErrorStore.self) private var errorStore
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<JournalEntry> { entry in entry.mergedInto == nil }) private var entries: [JournalEntry]

    @State private var actualBalance: Decimal?
    @State private var resultText: String?

    var body: some View {
        let currentBalance = calculateBalance(account: account, entries: entries)

        Form {
            Section {
                LabeledContent("По приложению", value: formatTenge(currentBalance))
                MoneyField(title: "Сейчас в Homebank", amount: $actualBalance)
            } footer: {
                Text(account.kind == .deposit
                     ? "Если в Homebank больше — разница запишется как проценты по депозиту."
                     : "Разница запишется корректировкой и не попадёт в траты и лимиты.")
            }
            Button("Сверить") { reconcile(currentBalance: currentBalance) }
                .disabled(actualBalance == nil)
            if let resultText {
                Text(resultText).foregroundStyle(theme.secondaryText)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .navigationTitle(account.title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть") { dismiss() }
            }
        }
    }

    private func reconcile(currentBalance: Decimal) {
        guard let actualBalance else { return }
        guard let adjustment = makeAdjustment(account: account, actualBalance: actualBalance, currentBalance: currentBalance, day: today) else {
            resultText = "Остаток совпадает, ничего записывать не нужно."
            return
        }
        do {
            try accountStore.addAdjustment(adjustment)
            dismiss()
        } catch {
            errorStore.show(error)
        }
    }
}
