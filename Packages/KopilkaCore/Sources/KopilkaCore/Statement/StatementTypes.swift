import Foundation

/// Строка текста на странице PDF: y отсчитывается от верха страницы, куски идут слева направо.
public struct TextLine: Sendable {
    public let pageIndex: Int
    public let y: Double
    public let pieces: [TextPiece]

    public init(pageIndex: Int, y: Double, pieces: [TextPiece]) {
        self.pageIndex = pageIndex
        self.y = y
        self.pieces = pieces
    }
}

/// Кусок текста строки; x — левый край в пунктах.
public struct TextPiece: Sendable {
    public let x: Double
    public let text: String

    public init(x: Double, text: String) {
        self.x = x
        self.text = text
    }
}

/// Строка таблицы операций. Расход и комиссия хранятся со знаком, как в выписке (отрицательные).
public struct StatementRow: Equatable, Sendable {
    public let operationDay: CalendarDay
    public let processingDay: CalendarDay
    public let description: String
    public let operationAmount: Decimal
    public let currency: String
    public let incomeAmount: Decimal
    public let expenseAmount: Decimal
    public let feeAmount: Decimal
    public let cardOrAccount: String
}

/// Итоги «Всего:» в том же знаке, что и строки.
public struct StatementTotals: Equatable, Sendable {
    public let income: Decimal
    public let expense: Decimal
    public let fee: Decimal
}

public struct StatementHeader: Sendable {
    public let accountNumber: String
    public let accountType: String
    public let periodStart: CalendarDay
    public let periodEnd: CalendarDay
    public let generatedOn: CalendarDay
    public let openingBalance: Decimal
    public let closingBalance: Decimal
    public let availableAmount: Decimal?
    public let totals: StatementTotals
}

public struct ParsedStatement: Sendable {
    public let header: StatementHeader
    public let rows: [StatementRow]
}

public enum StatementError: Error, Equatable {
    case notHalykStatement
    case totalsMismatch(expected: StatementTotals, actual: StatementTotals)
}
