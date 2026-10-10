import Foundation
import Observation
import SwiftData
import KopilkaCore

/// Счета: поиск, добавление и точка отсчёта остатка (спека §5.9). Каждый метод, который пишет, сохраняет базу.
@Observable
final class AccountStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func findAccount(number: String) throws -> Account? {
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate { account in account.number == number })
        return try context.fetch(descriptor).first
    }

    /// Депозит может уже быть: импорт заводит его без номера, когда в выписке карты есть пополнения депозита.
    /// Номер подставит импорт выписки самого депозита.
    func findOrAddDepositAccount() throws -> Account {
        let accounts = try context.fetch(FetchDescriptor<Account>())
        if let depositAccount = accounts.first(where: { account in account.kind == .deposit }) {
            return depositAccount
        }
        return try addAccount(kind: .deposit, title: "Депозит", number: "")
    }

    func addAccount(kind: AccountKind, title: String, number: String) throws -> Account {
        let account = Account(kind: kind, title: title, number: number)
        context.insert(account)
        try context.save()
        return account
    }

    func updateAnchor(_ account: Account, balance: Decimal, day: CalendarDay) throws {
        account.anchorBalance = balance
        account.anchorDay = day
        try context.save()
    }

    /// «Сверить остаток»: запись-корректировка на разницу (её строит makeAdjustment в ядре).
    func addAdjustment(_ entry: JournalEntry) throws {
        context.insert(entry)
        try context.save()
    }

    func updateTitle(_ account: Account, title: String) throws {
        account.title = title
        try context.save()
    }
}
