import Foundation
import Testing
@testable import KopilkaCore

struct StatementTableReaderTests {
    @Test func readsRowWithMultilineDescription() throws {
        let lines = makePreambleLines(shiftX: 0) + [
            makeTableHeaderLine(pageIndex: 0, y: 300, shiftX: 0),
            makeTotalsLine(pageIndex: 0, y: 320, shiftX: 0),
            makeRowLine(pageIndex: 0, y: 340, shiftX: 0, description: "Операция оплаты у", expense: "-1 398,00"),
            makeContinuationLine(pageIndex: 0, y: 349, shiftX: 0, text: "коммерсанта"),
            makeContinuationLine(pageIndex: 0, y: 358, shiftX: 0, text: "MAGNUM.ASF36."),
        ]

        let statement = try readStatement(lines: lines)

        let expectedRow = StatementRow(
            operationDay: CalendarDay(year: 2026, month: 1, day: 13),
            processingDay: CalendarDay(year: 2026, month: 1, day: 15),
            description: "Операция оплаты у коммерсанта MAGNUM.ASF36.",
            operationAmount: -1398,
            currency: "KZT",
            incomeAmount: 0,
            expenseAmount: -1398,
            feeAmount: 0,
            cardOrAccount: "552204******2936"
        )
        #expect(statement.rows == [expectedRow])
    }

    @Test func continuationAfterPageBreakJoinsPreviousRow() throws {
        let lines = makePreambleLines(shiftX: 0) + [
            makeTableHeaderLine(pageIndex: 0, y: 300, shiftX: 0),
            makeTotalsLine(pageIndex: 0, y: 320, shiftX: 0),
            makeRowLine(pageIndex: 0, y: 340, shiftX: 0, description: "Операция оплаты у", expense: "-1 398,00"),
            TextLine(pageIndex: 0, y: 800, pieces: [TextPiece(x: 23, text: "Выписка по счету: KZ126010002008249310 1")]),
            // На новой странице банк повторяет заголовок таблицы в несколько строк.
            TextLine(pageIndex: 1, y: 20, pieces: [TextPiece(x: 35, text: "Дата"), TextPiece(x: 81, text: "Дата")]),
            TextLine(pageIndex: 1, y: 29, pieces: [
                TextPiece(x: 23, text: "проведения"), TextPiece(x: 71, text: "обработки"),
                TextPiece(x: 128, text: "Описание операции"), TextPiece(x: 228, text: "Сумма"),
                TextPiece(x: 273, text: "Валюта"), TextPiece(x: 325, text: "Приход в"),
                TextPiece(x: 392, text: "Расход в"), TextPiece(x: 447, text: "Комиссия"),
                TextPiece(x: 500, text: "№ карточки/счета"),
            ]),
            TextLine(pageIndex: 1, y: 38, pieces: [
                TextPiece(x: 26, text: "операции"), TextPiece(x: 73, text: "операции"),
                TextPiece(x: 223, text: "операции"), TextPiece(x: 270, text: "операции"),
                TextPiece(x: 318, text: "валюте счета"), TextPiece(x: 383, text: "валюте счета"),
            ]),
            makeContinuationLine(pageIndex: 1, y: 50, shiftX: 0, text: "коммерсанта MAGNUM"),
            makeRowLine(pageIndex: 1, y: 60, shiftX: 0, description: "Перевод на другую карту", expense: "-500,00"),
        ]

        let statement = try readStatement(lines: lines)

        let descriptions = statement.rows.map { row in row.description }
        #expect(descriptions == ["Операция оплаты у коммерсанта MAGNUM", "Перевод на другую карту"])
    }

    @Test func columnsDetectedFromHeaderPositions() throws {
        let baseStatement = try readStatement(lines: makeOneRowStatementLines(shiftX: 0))
        let shiftedStatement = try readStatement(lines: makeOneRowStatementLines(shiftX: 20))

        #expect(shiftedStatement.rows == baseStatement.rows)
        #expect(shiftedStatement.rows.count == 1)
    }

    @Test func missingTableHeaderThrowsNotHalyk() {
        let lines = makePreambleLines(shiftX: 0) + [
            makeRowLine(pageIndex: 0, y: 340, shiftX: 0, description: "Перевод", expense: "-500,00"),
        ]

        #expect(throws: StatementError.notHalykStatement) {
            try readStatement(lines: lines)
        }
    }

    @Test func readsHeaderFieldsByLabels() throws {
        let statement = try readStatement(lines: makeOneRowStatementLines(shiftX: 0))

        let header = statement.header
        #expect(header.accountNumber == "KZ126010002008249310")
        #expect(header.accountType == "Текущий счет в карточной базе («Зарплата»)")
        #expect(header.periodStart == CalendarDay(year: 2026, month: 1, day: 1))
        #expect(header.periodEnd == CalendarDay(year: 2026, month: 1, day: 31))
        #expect(header.generatedOn == CalendarDay(year: 2026, month: 1, day: 31))
        #expect(header.openingBalance == Decimal(string: "1000.50"))
        #expect(header.closingBalance == -10)
        #expect(header.availableAmount == Decimal(string: "6933.41"))
        #expect(header.totals == StatementTotals(income: 0, expense: -1398, fee: 0))
    }

    @Test func labelsMatchWithoutSpaces() throws {
        let lines = makeOneRowStatementLines(shiftX: 0).map { line in
            TextLine(pageIndex: line.pageIndex, y: line.y, pieces: line.pieces.map { piece in
                TextPiece(x: piece.x, text: piece.text.replacingOccurrences(of: "Номер счета: ", with: "Номерсчета:"))
            })
        }

        let statement = try readStatement(lines: lines)

        #expect(statement.header.accountNumber == "KZ126010002008249310")
    }

    @Test func missingAvailableAmountGivesNil() throws {
        let lines = makeOneRowStatementLines(shiftX: 0).filter { line in
            !line.pieces.contains { piece in piece.text.hasPrefix("Доступная") || piece.text.hasPrefix("на дату") }
        }

        let statement = try readStatement(lines: lines)

        #expect(statement.header.availableAmount == nil)
    }

    @Test func emptyCurrencyRowIsRead() throws {
        let lines = makePreambleLines(shiftX: 0) + [
            makeTableHeaderLine(pageIndex: 0, y: 300, shiftX: 0),
            makeTotalsLine(pageIndex: 0, y: 320, shiftX: 0),
            TextLine(pageIndex: 0, y: 340, pieces: [
                TextPiece(x: 26, text: "10.10.2025"), TextPiece(x: 72, text: "10.10.2025"),
                TextPiece(x: 120, text: "Ежемесячная комиссия за"), TextPiece(x: 234, text: "0,00"),
                TextPiece(x: 335, text: "0,00"), TextPiece(x: 400, text: "0,00"),
                TextPiece(x: 453, text: "-150,00"), TextPiece(x: 501, text: "552204******2936"),
            ]),
        ]

        let statement = try readStatement(lines: lines)

        #expect(statement.rows.count == 1)
        #expect(statement.rows.first?.currency == "")
        #expect(statement.rows.first?.operationAmount == 0)
        #expect(statement.rows.first?.feeAmount == -150)
    }

    @Test func badAmountInRowThrows() {
        let lines = makePreambleLines(shiftX: 0) + [
            makeTableHeaderLine(pageIndex: 0, y: 300, shiftX: 0),
            makeTotalsLine(pageIndex: 0, y: 320, shiftX: 0),
            makeRowLine(pageIndex: 0, y: 340, shiftX: 0, description: "Перевод", expense: "-12abc"),
        ]

        #expect(throws: ParsingError.badAmount("-12abc")) {
            try readStatement(lines: lines)
        }
    }

    @Test func checkTotalsPassesWhenSumsMatch() throws {
        let statement = try readStatement(lines: makeOneRowStatementLines(shiftX: 0))

        try checkTotals(statement)
    }

    @Test func checkTotalsThrowsOnMismatch() throws {
        let lines = makePreambleLines(shiftX: 0) + [
            makeTableHeaderLine(pageIndex: 0, y: 300, shiftX: 0),
            makeTotalsLine(pageIndex: 0, y: 320, shiftX: 0),
            makeRowLine(pageIndex: 0, y: 340, shiftX: 0, description: "Перевод", expense: "-1 000,00"),
        ]
        let statement = try readStatement(lines: lines)

        #expect(throws: StatementError.totalsMismatch(
            expected: StatementTotals(income: 0, expense: -1398, fee: 0),
            actual: StatementTotals(income: 0, expense: -1000, fee: 0)
        )) {
            try checkTotals(statement)
        }
    }
}

// Координаты x близки к реальной выписке Halyk: левый край текста в каждой колонке.
private func makePreambleLines(shiftX: Double) -> [TextLine] {
    [
        TextLine(pageIndex: 0, y: 100, pieces: [
            TextPiece(x: 23 + shiftX, text: "ФИО: ИВАНОВ ИВАН"),
            TextPiece(x: 340 + shiftX, text: "Дата формирования выписки: 31.01.2026"),
        ]),
        TextLine(pageIndex: 0, y: 109, pieces: [
            TextPiece(x: 340 + shiftX, text: "Период выписки: с 01.01.2026 по 31.01.2026"),
        ]),
        TextLine(pageIndex: 0, y: 127, pieces: [
            TextPiece(x: 23 + shiftX, text: "Тип счета: Текущий счет в карточной базе («Зарплата»)"),
        ]),
        TextLine(pageIndex: 0, y: 136, pieces: [
            TextPiece(x: 23 + shiftX, text: "Номер счета: KZ126010002008249310"),
            TextPiece(x: 340 + shiftX, text: "Входящий остаток: 1 000,50"),
        ]),
        TextLine(pageIndex: 0, y: 145, pieces: [
            TextPiece(x: 23 + shiftX, text: "Валюта счета: KZT"),
            TextPiece(x: 340 + shiftX, text: "Исходящий остаток: -10,00"),
        ]),
        TextLine(pageIndex: 0, y: 154, pieces: [
            TextPiece(x: 23 + shiftX, text: "Номер карточки: 552204******2936"),
            TextPiece(x: 340 + shiftX, text: "Доступная сумма с учетом кредитного лимита"),
        ]),
        TextLine(pageIndex: 0, y: 163, pieces: [
            TextPiece(x: 340 + shiftX, text: "на дату формирования выписки: 6 933,41"),
        ]),
    ]
}

private func makeTableHeaderLine(pageIndex: Int, y: Double, shiftX: Double) -> TextLine {
    TextLine(pageIndex: pageIndex, y: y, pieces: [
        TextPiece(x: 35 + shiftX, text: "Дата проведения операции"),
        TextPiece(x: 81 + shiftX, text: "Дата обработки операции"),
        TextPiece(x: 128 + shiftX, text: "Описание операции"),
        TextPiece(x: 228 + shiftX, text: "Сумма операции"),
        TextPiece(x: 273 + shiftX, text: "Валюта операции"),
        TextPiece(x: 325 + shiftX, text: "Приход в валюте счета"),
        TextPiece(x: 392 + shiftX, text: "Расход в валюте счета"),
        TextPiece(x: 447 + shiftX, text: "Комиссия"),
        TextPiece(x: 500 + shiftX, text: "№ карточки/счета"),
    ])
}

private func makeTotalsLine(pageIndex: Int, y: Double, shiftX: Double) -> TextLine {
    TextLine(pageIndex: pageIndex, y: y, pieces: [
        TextPiece(x: 32 + shiftX, text: "Всего:"),
        TextPiece(x: 334 + shiftX, text: "0,00"),
        TextPiece(x: 388 + shiftX, text: "-1 398,00"),
        TextPiece(x: 457 + shiftX, text: "0,00"),
    ])
}

private func makeRowLine(pageIndex: Int, y: Double, shiftX: Double, description: String, expense: String) -> TextLine {
    TextLine(pageIndex: pageIndex, y: y, pieces: [
        TextPiece(x: 26 + shiftX, text: "13.01.2026"),
        TextPiece(x: 72 + shiftX, text: "15.01.2026"),
        TextPiece(x: 131 + shiftX, text: description),
        TextPiece(x: 225 + shiftX, text: expense),
        TextPiece(x: 279 + shiftX, text: "KZT"),
        TextPiece(x: 335 + shiftX, text: "0,00"),
        TextPiece(x: 392 + shiftX, text: expense),
        TextPiece(x: 458 + shiftX, text: "0,00"),
        TextPiece(x: 501 + shiftX, text: "552204******2936"),
    ])
}

private func makeContinuationLine(pageIndex: Int, y: Double, shiftX: Double, text: String) -> TextLine {
    TextLine(pageIndex: pageIndex, y: y, pieces: [TextPiece(x: 142 + shiftX, text: text)])
}

private func makeOneRowStatementLines(shiftX: Double) -> [TextLine] {
    makePreambleLines(shiftX: shiftX) + [
        makeTableHeaderLine(pageIndex: 0, y: 300, shiftX: shiftX),
        makeTotalsLine(pageIndex: 0, y: 320, shiftX: shiftX),
        makeRowLine(pageIndex: 0, y: 340, shiftX: shiftX, description: "Операция оплаты у", expense: "-1 398,00"),
        makeContinuationLine(pageIndex: 0, y: 349, shiftX: shiftX, text: "коммерсанта MAGNUM"),
    ]
}
