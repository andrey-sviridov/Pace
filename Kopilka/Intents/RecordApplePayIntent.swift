import AppIntents
import Foundation
import KopilkaCore

/// Автоматизация «Транзакция» (Apple Pay) → это действие (спека §5.10). Окно приложения не открывается.
struct RecordApplePayIntent: AppIntent {
    static let title: LocalizedStringResource = "Записать оплату в Копилку"
    static let description = IntentDescription("Записывает оплату Apple Pay в Копилку.")
    static let openAppWhenRun = false

    @Parameter(title: "Продавец")
    var merchant: String

    @Parameter(title: "Сумма")
    var amount: Double

    @Parameter(title: "Валюта", default: "KZT")
    var currency: String

    @Parameter(title: "Карта", default: "")
    var card: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let context = try openIntentContext()
        let settings = try loadIntentSettings(context: context)
        // Источник выключен — молча пропускаем: автоматизацию можно не удалять.
        guard settings.isApplePayEnabled else { return .result(value: "") }

        // «Команды» отдают сумму как Double; в деньги переводим через текст с двумя знаками,
        // чтобы 1500.1 не превратилось в 1500.0999999.
        guard let amountTenge = Decimal(string: String(format: "%.2f", amount)), amountTenge > 0 else {
            throw IntentRecordingError.badAmount
        }

        let now = Date()
        let entry = try recordIntentOperation(
            kind: .applePay,
            type: .expense,
            amount: amountTenge,
            rawMerchant: merchant,
            rawText: "\(merchant) · \(amount) \(currency) · \(card)",
            now: now,
            context: context
        )
        let remainingText = try makeIntentRemainingText(for: entry, settings: settings, now: now, context: context)
        return .result(value: remainingText)
    }
}
