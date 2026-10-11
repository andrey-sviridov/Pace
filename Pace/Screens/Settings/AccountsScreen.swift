import SwiftUI
import SwiftData
import PaceCore

/// «Мои счета»: карты Halyk, депозиты и другие свои карты. Новую карту можно добавить сюда,
/// чтобы её выписка загружалась без вопроса «неизвестный счёт», а переводы на неё не считались тратами.
struct AccountsScreen: View {
    let today: CalendarDay

    @Environment(\.theme) private var theme

    @Query(sort: \Account.title) private var accounts: [Account]
    @Query(filter: #Predicate<JournalEntry> { entry in entry.mergedInto == nil }) private var entries: [JournalEntry]

    @State private var isAddingAccount = false

    var body: some View {
        List {
            AccountGroup(title: "Карты Halyk", accounts: accounts.filter { account in account.kind == .card }, entries: entries, today: today)
            AccountGroup(title: "Депозиты", accounts: accounts.filter { account in account.kind == .deposit }, entries: entries, today: today)
            AccountGroup(title: "Другие свои карты", accounts: accounts.filter { account in account.kind == .ownOtherCard }, entries: entries, today: today)
            Section {
                Button("Добавить счёт") { isAddingAccount = true }
            } footer: {
                Text("Переводы между своими счетами не считаются тратами. В выписке Halyk получатель перевода не указан, поэтому перевод узнаётся по выписке второго счёта или по правилу суммы.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .navigationTitle("Мои счета")
        .sheet(isPresented: $isAddingAccount) {
            NavigationStack { AddAccountScreen() }
        }
    }
}

private struct AccountGroup: View {
    let title: String
    let accounts: [Account]
    let entries: [JournalEntry]
    let today: CalendarDay

    var body: some View {
        if !accounts.isEmpty {
            Section(title) {
                ForEach(accounts) { account in
                    NavigationLink {
                        AccountScreen(account: account, today: today)
                    } label: {
                        AccountRow(account: account, balance: account.kind == .ownOtherCard ? nil : calculateBalance(account: account, entries: entries))
                    }
                }
            }
        }
    }
}

private struct AccountRow: View {
    let account: Account
    /// У других своих карт остаток не ведём: их выписки не загружаются.
    let balance: Decimal?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.title)
                if !account.number.isEmpty {
                    Text(account.number).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let balance {
                Text(formatTenge(balance)).monospacedDigit()
            }
        }
    }
}

/// Один счёт: название, номер, сверка остатка (у другой своей карты остатка нет — её выписку мы не грузим).
private struct AccountScreen: View {
    let account: Account
    let today: CalendarDay

    @Environment(AccountStore.self) private var accountStore
    @Environment(ErrorStore.self) private var errorStore
    @Environment(\.theme) private var theme

    @State private var title = ""
    @State private var isReconciling = false

    var body: some View {
        Form {
            Section("Название") {
                TextField("Карта *2936", text: $title)
                    .onSubmit(saveTitle)
            }
            if !account.number.isEmpty {
                LabeledContent("Номер счёта", value: account.number)
            }
            if account.kind != .ownOtherCard {
                Button("Сверить остаток") { isReconciling = true }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .navigationTitle(account.title)
        .onAppear { title = account.title }
        .sheet(isPresented: $isReconciling) {
            NavigationStack { ReconcileScreen(account: account, today: today) }
        }
    }

    private func saveTitle() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else {
            title = account.title
            return
        }
        do {
            try accountStore.updateTitle(account, title: trimmedTitle)
        } catch {
            errorStore.show(error)
        }
    }
}

private struct AddAccountScreen: View {
    @Environment(AccountStore.self) private var accountStore
    @Environment(ErrorStore.self) private var errorStore
    @Environment(\.dismiss) private var dismiss

    @State private var kind = AccountKind.card
    @State private var title = ""
    @State private var number = ""

    var body: some View {
        Form {
            Picker("Вид", selection: $kind) {
                Text("Карта Halyk").tag(AccountKind.card)
                Text("Депозит").tag(AccountKind.deposit)
                Text("Другая своя карта").tag(AccountKind.ownOtherCard)
            }
            TextField("Название, например «Карта *4512»", text: $title)
            TextField("Номер счёта KZ… (из шапки выписки)", text: $number)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        }
        .navigationTitle("Новый счёт")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Добавить", action: addAccount)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addAccount() {
        do {
            _ = try accountStore.addAccount(
                kind: kind,
                title: title.trimmingCharacters(in: .whitespaces),
                number: number.replacingOccurrences(of: " ", with: "")
            )
            dismiss()
        } catch {
            errorStore.show(error)
        }
    }
}
