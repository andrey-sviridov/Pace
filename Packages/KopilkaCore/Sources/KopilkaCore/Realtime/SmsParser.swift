import Foundation

public struct ParsedSms: Equatable, Sendable {
    public let amount: Decimal
    public let isIncome: Bool
    public let merchant: String?
    public let balance: Decimal?
}

/// Общий шаблон SMS банка, пока нет реальных образцов. Нет суммы — `nil`, и SMS уходит в «не разобрано».
public func parseSms(_ text: String) -> ParsedSms? {
    guard let foundAmount = findAmount(in: text) else { return nil }
    return ParsedSms(
        amount: foundAmount.amount,
        isIncome: findIsIncome(in: text),
        merchant: findMerchant(in: text, after: foundAmount.endIndex),
        balance: findBalance(in: text)
    )
}

/// Запись для экрана «Проверьте новое», когда SMS не разобралось.
/// Единственное место, где сумма равна нулю (в остальном она всегда больше нуля): это заглушка,
/// а вид «корректировка» вместе с `affectsBalance = false` выводит её из всех денежных расчётов.
public func makeUnparsedSmsEntry(text: String, now: Date, calendar: Calendar) -> JournalEntry {
    let components = calendar.dateComponents([.year, .month, .day], from: now)
    guard let year = components.year, let month = components.month, let day = components.day else {
        preconditionFailure("Calendar обязан вернуть год, месяц и день")
    }
    let entry = JournalEntry(
        day: CalendarDay(year: year, month: month, day: day),
        time: now,
        type: .adjustment,
        amount: 0,
        title: "SMS не разобрано",
        categoryId: nil,
        note: text,
        isReviewed: false,
        affectsBalance: false,
        createdAt: now
    )
    let source = SourceRecord(
        kind: .sms,
        key: "sms:unparsed:\(ISO8601DateFormatter().string(from: now)):\(text)",
        receivedAt: now,
        rawText: text
    )
    entry.sources.append(source)
    return entry
}

private struct FoundAmount {
    let amount: Decimal
    let endIndex: String.Index
}

/// Первая сумма с валютой: `1 500,00 KZT`, `1500 ₸`, `1500.00 KZT`.
private func findAmount(in text: String) -> FoundAmount? {
    let amountRegex = /(?:^|\D)(\d{1,3}(?:[ \u{00A0}]\d{3})+|\d+)([.,]\d{1,2})?\s*(?:KZT|₸|тг|тенге)/.ignoresCase()
    guard let match = text.firstMatch(of: amountRegex),
          let amount = parseDecimal(String(match.1) + String(match.2 ?? ""))
    else { return nil }
    return FoundAmount(amount: amount, endIndex: match.range.upperBound)
}

private func findIsIncome(in text: String) -> Bool {
    let incomeRegex = /зачисл|поступл|пополн/.ignoresCase()
    return text.firstMatch(of: incomeRegex) != nil
}

/// Продавец: текст после «в »/«at »/«оплата »; нет слова — текст сразу после суммы. Оба варианта до слова «остаток».
private func findMerchant(in text: String, after amountEnd: String.Index) -> String? {
    let tail = String(text[amountEnd...])
    let markerRegex = /(?:^|\s)(?:в|at|оплата)\s+(.+?)(?=\s+(?:остаток|баланс|дост\w*)|$)/.ignoresCase()
    let tailRegex = /^(?!\s*(?:остаток|баланс|дост))\s*(.+?)(?=\s+(?:остаток|баланс|дост\w*)|$)/.ignoresCase()

    let rawMerchant = tail.firstMatch(of: markerRegex).map { match in String(match.1) }
        ?? tail.firstMatch(of: tailRegex).map { match in String(match.1) }
    let merchant = rawMerchant?.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    guard let merchant, !merchant.isEmpty else { return nil }
    return merchant
}

private func findBalance(in text: String) -> Decimal? {
    let balanceRegex = /(?:остаток|баланс|дост\w*)[:\s]*(\d{1,3}(?:[ \u{00A0}]\d{3})+|\d+)([.,]\d{1,2})?/.ignoresCase()
    guard let match = text.firstMatch(of: balanceRegex) else { return nil }
    return parseDecimal(String(match.1) + String(match.2 ?? ""))
}

/// Формат уже проверен регулярным выражением, поэтому сбой разбора значит «числа нет».
private func parseDecimal(_ text: String) -> Decimal? {
    do {
        return try parseAmount(text)
    } catch {
        return nil
    }
}
