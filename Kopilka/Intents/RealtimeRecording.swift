import Foundation
import SwiftData
import KopilkaCore

// Общие шаги для «Команд» (Apple Pay и SMS). Каждый шаг — одно действие, интенты вызывают их по порядку.

/// «Команда» запускается без окна приложения, поэтому корня с готовым контейнером нет.
/// Это единственное место, где база открывается не в KopilkaApp: тот же файл на диске, то же приложение.
@MainActor
func openIntentContext() throws -> ModelContext {
    let container = try makeModelContainer(inMemory: false)
    return container.mainContext
}

/// Настроек может не быть, если приложение ещё ни разу не открывали: тогда действуют значения по умолчанию
/// (оба источника выключены), и команда ничего не запишет.
func loadIntentSettings(context: ModelContext) throws -> AppSettings {
    try context.fetch(FetchDescriptor<AppSettings>()).first ?? AppSettings()
}

/// Операция из Apple Pay или SMS: склеивается с уже пришедшей из другого источника или создаётся новой.
func recordIntentOperation(
    kind: SourceKind,
    type: EntryType,
    amount: Decimal,
    rawMerchant: String,
    rawText: String?,
    now: Date,
    context: ModelContext
) throws -> JournalEntry {
    let cardAccount = try findCardAccount(context: context)
    let rules = try context.fetch(FetchDescriptor<MerchantRule>())
    let salaryHistory = try loadSalaryHistory(context: context)
    return try recordRealtimeOperation(
        kind: kind,
        day: makeCalendarDay(date: now, calendar: .current),
        time: now,
        type: type,
        amount: amount,
        rawMerchant: rawMerchant,
        rawText: rawText,
        account: cardAccount,
        rules: rules,
        salaryHistory: salaryHistory,
        salaryMinShareOfMedian: 0.5,
        context: context,
        now: now
    )
}

/// «Кафе: осталось 4 200 из 30 000» — только если пользователь включил это в настройках и категория у порога.
/// Пустая строка означает «ничего не показывать».
func makeIntentRemainingText(for entry: JournalEntry, settings: AppSettings, now: Date, context: ModelContext) throws -> String {
    guard settings.shouldShowRemainingAfterPayment else { return "" }

    let entries = try context.fetch(FetchDescriptor<JournalEntry>())
    let categories = try context.fetch(FetchDescriptor<SpendingCategory>())
    let today = makeCalendarDay(date: now, calendar: .current)
    let salaryEvents = findSalaryEvents(entries: entries, advanceDayRange: SalaryDetection.advanceDayRange, oneOffAboveMedianTimes: SalaryDetection.oneOffAboveMedianTimes)
    let period = makePeriod(containing: today, mode: settings.periodMode, salaryEvents: salaryEvents)
    let statuses = calculateLimitStatuses(period: period, today: today, mode: settings.periodMode, entries: entries, categories: categories)
    return makeRemainingAfterPaymentText(categoryId: entry.categoryId, statuses: statuses) ?? ""
}

private func findCardAccount(context: ModelContext) throws -> Account {
    let accounts = try context.fetch(FetchDescriptor<Account>())
    guard let cardAccount = accounts.first(where: { account in account.kind == .card }) else {
        throw IntentRecordingError.noCardAccount
    }
    return cardAccount
}

private func loadSalaryHistory(context: ModelContext) throws -> [Decimal] {
    let entries = try context.fetch(FetchDescriptor<JournalEntry>())
    let salaryEntries = entries.filter { entry in entry.categoryId == "salary" && entry.mergedInto == nil }
    return salaryEntries.map { entry in entry.amount }
}

enum IntentRecordingError: LocalizedError {
    case noCardAccount
    case badAmount

    var errorDescription: String? {
        switch self {
        case .noCardAccount: "Сначала откройте Копилку и загрузите выписку карты."
        case .badAmount: "Не получилось прочитать сумму оплаты."
        }
    }
}
