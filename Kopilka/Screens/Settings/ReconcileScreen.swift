import SwiftUI
import SwiftData
import KopilkaCore

/// «Сверить остаток» (спека §5.9): ввели, что показывает Homebank, — разница записывается корректировкой.
/// Плюс по депозиту — «Проценты по депозиту». В траты и лимиты корректировка не идёт.
struct ReconcileScreen: View {
    let today: CalendarDay

    @Environment(AccountStore.self) private var accountStore
    @Environment(ErrorStore.self) private var errorStore
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @Query private var accounts: [Account]
    @Query(filter: #Predicate<JournalEntry> { entry in entry.mergedInto == nil }) private var entries: [JournalEntry]

    @State private var selectedAccountIndex = 0
    @State private var actualBalance: Decimal?
    @State private var resultText: String?

    var body: some View {
        let ownAccounts = accounts.filter { account in account.kind == .card || account.kind == .deposit }

        Form {
            if ownAccounts.isEmpty {
                Text("Счетов пока нет — сначала загрузите выписку.")
            } else {
                let account = ownAccounts[min(selectedAccountIndex, ownAccounts.count - 1)]
                let currentBalance = calculateBalance(account: account, entries: entries)

                Picker("Счёт", selection: $selectedAccountIndex) {
                    ForEach(ownAccounts.indices, id: \.self) { index in
                        Text(ownAccounts[index].title).tag(index)
                    }
                }
                LabeledContent("По приложению", value: formatTenge(currentBalance))
                MoneyField(title: "Сейчас в Homebank", amount: $actualBalance)
                Button("Сверить") { reconcile(account: account, currentBalance: currentBalance) }
                    .disabled(actualBalance == nil)
                if let resultText {
                    Text(resultText).foregroundStyle(theme.secondaryText)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .navigationTitle("Сверить остаток")
    }

    private func reconcile(account: Account, currentBalance: Decimal) {
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
