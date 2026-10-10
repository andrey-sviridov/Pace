import AppIntents
import Foundation
import KopilkaCore

/// Автоматизация «Сообщение» от Halyk → это действие (спека §5.10). Окно приложения не открывается.
struct ParseSmsIntent: AppIntent {
    static let title: LocalizedStringResource = "Разобрать SMS Halyk"
    static let description = IntentDescription("Записывает операцию из SMS банка в Копилку.")
    static let openAppWhenRun = false

    @Parameter(title: "Текст SMS")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let context = try openIntentContext()
        let settings = try loadIntentSettings(context: context)
        // Источник выключен — молча пропускаем: автоматизацию можно не удалять.
        guard settings.isSmsEnabled else { return .result(value: "") }

        let now = Date()
        guard let sms = parseSms(text) else {
            // Не разобралось — SMS не теряется: попадает в «Проверьте новое» как есть.
            context.insert(makeUnparsedSmsEntry(text: text, now: now, calendar: .current))
            try context.save()
            return .result(value: "")
        }

        let entry = try recordIntentOperation(
            kind: .sms,
            type: sms.isIncome ? .income : .expense,
            amount: sms.amount,
            rawMerchant: sms.merchant ?? "",
            rawText: text,
            now: now,
            context: context
        )
        let remainingText = try makeIntentRemainingText(for: entry, settings: settings, now: now, context: context)
        return .result(value: remainingText)
    }
}
