import CryptoKit
import Foundation

public struct KeyedRow: Equatable, Sendable {
    public let row: StatementRow
    /// "<базовый ключ>#<номер среди одинаковых строк файла>".
    public let key: String
}

/// Ключ строки по исходнику выписки (спека §5.2). Дата обработки не входит: между выписками она может меняться.
public func makeBaseKey(row: StatementRow, accountNumber: String) -> String {
    // Суммы через "\(decimal)": у Decimal это всегда точка и без хвостовых нулей, формат не зависит от локали.
    let keySource = [
        accountNumber,
        "\(row.operationDay.year)-\(row.operationDay.month)-\(row.operationDay.day)",
        "\(row.operationAmount)",
        row.currency,
        "\(row.incomeAmount)",
        "\(row.expenseAmount)",
        "\(row.feeAmount)",
        row.cardOrAccount,
        normalizeDescription(row.description),
    ].joined(separator: "|")

    let digest = SHA256.hash(data: Data(keySource.utf8))
    return digest.map { byte in String(format: "%02x", byte) }.joined()
}

/// Одинаковые строки различаются порядком в файле: считаем с 1.
public func makeKeyedRows(rows: [StatementRow], accountNumber: String) -> [KeyedRow] {
    var occurrenceCountByBaseKey: [String: Int] = [:]
    return rows.map { row in
        let baseKey = makeBaseKey(row: row, accountNumber: accountNumber)
        let occurrenceNumber = (occurrenceCountByBaseKey[baseKey] ?? 0) + 1
        occurrenceCountByBaseKey[baseKey] = occurrenceNumber
        return KeyedRow(row: row, key: "\(baseKey)#\(occurrenceNumber)")
    }
}
