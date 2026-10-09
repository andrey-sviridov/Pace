import Foundation

/// Разбирает строки текста выписки Halyk: шапку до таблицы, итоги «Всего:» и строки операций.
public func readStatement(lines: [TextLine]) throws -> ParsedStatement {
    guard let tableHeaderIndex = lines.firstIndex(where: { line in isTableHeaderLine(line) }) else {
        throw StatementError.notHalykStatement
    }
    let preambleLines = Array(lines[..<tableHeaderIndex])
    let tableLines = Array(lines[tableHeaderIndex...])

    // Заголовок таблицы занимает несколько строк, метки колонок собираем со всех.
    let tableHeaderLines = tableLines.prefix { line in isTableHeaderLine(line) }
    let tableHeaderPieces = tableHeaderLines.flatMap { line in line.pieces }
    let boundariesX = try findColumnBoundariesX(tableHeaderPieces: tableHeaderPieces)

    guard let totalsLine = tableLines.first(where: { line in isTotalsLine(line) }) else {
        throw StatementError.notHalykStatement
    }
    let totals = try readTotals(totalsLine: totalsLine, boundariesX: boundariesX)
    let header = try readHeader(preambleLines: preambleLines, totals: totals, sameColumnToleranceX: 2)
    let rows = try readRows(tableLines: tableLines, boundariesX: boundariesX)
    return ParsedStatement(header: header, rows: rows)
}

/// Сверяет суммы строк с итогами «Всего:» из выписки.
public func checkTotals(_ statement: ParsedStatement) throws {
    let rows = statement.rows
    let actualTotals = StatementTotals(
        income: rows.reduce(Decimal(0)) { sum, row in sum + row.incomeAmount },
        expense: rows.reduce(Decimal(0)) { sum, row in sum + row.expenseAmount },
        fee: rows.reduce(Decimal(0)) { sum, row in sum + row.feeAmount }
    )
    guard actualTotals == statement.header.totals else {
        throw StatementError.totalsMismatch(expected: statement.header.totals, actual: actualTotals)
    }
}

// MARK: - Колонки таблицы

private enum StatementColumn: CaseIterable {
    case operationDay, processingDay, description, operationAmount, currency, income, expense, fee, cardOrAccount
}

// Банк повторяет заголовок таблицы на каждой странице и переносит метки по словам
// («Дата / проведения / операции»), поэтому узнаём строку заголовка по словам, а не целиком.
// Строка продолжения описания — всегда один кусок, поэтому требуем хотя бы два.
private func isTableHeaderLine(_ line: TextLine) -> Bool {
    let headerWordPrefixes = [
        "ДАТА", "ПРОВЕДЕНИЯ", "ОБРАБОТКИ", "ОПЕРАЦИИ", "ОПИСАНИЕ", "СУММА",
        "ВАЛЮТ", "ПРИХОД", "РАСХОД", "КОМИССИЯ", "№КАРТОЧКИ",
    ]
    guard line.pieces.count >= 2 else { return false }
    return line.pieces.allSatisfy { piece in
        let normalizedText = normalizeDescription(piece.text)
        return headerWordPrefixes.contains { prefix in normalizedText.hasPrefix(prefix) }
    }
}

private func isTotalsLine(_ line: TextLine) -> Bool {
    guard let firstPiece = line.pieces.first else { return false }
    return normalizeDescription(firstPiece.text).hasPrefix("ВСЕГО")
}

/// Границы колонок — середины между левыми краями соседних меток заголовка.
private func findColumnBoundariesX(tableHeaderPieces: [TextPiece]) throws -> [Double] {
    let datePiecesX = tableHeaderPieces
        .filter { piece in normalizeDescription(piece.text).hasPrefix("ДАТА") }
        .map { piece in piece.x }
        .sorted()
    guard datePiecesX.count == 2 else {
        throw StatementError.notHalykStatement
    }

    let otherLabelPrefixes = ["ОПИСАНИЕ", "СУММА", "ВАЛЮТА", "ПРИХОД", "РАСХОД", "КОМИССИЯ", "№КАРТОЧКИ"]
    var labelsX = datePiecesX
    for prefix in otherLabelPrefixes {
        guard let labelPiece = tableHeaderPieces.first(where: { piece in normalizeDescription(piece.text).hasPrefix(prefix) }) else {
            throw StatementError.notHalykStatement
        }
        labelsX.append(labelPiece.x)
    }
    guard labelsX == labelsX.sorted() else {
        throw StatementError.notHalykStatement
    }

    return zip(labelsX, labelsX.dropFirst()).map { leftX, rightX in (leftX + rightX) / 2 }
}

/// Раскладывает куски строки по колонкам; несколько кусков в одной колонке склеиваются через пробел.
private func makeCells(line: TextLine, boundariesX: [Double]) -> [StatementColumn: String] {
    var cells: [StatementColumn: String] = [:]
    for piece in line.pieces {
        let columnIndex = boundariesX.filter { boundaryX in piece.x >= boundaryX }.count
        let column = StatementColumn.allCases[columnIndex]
        let existingText = cells[column].map { text in text + " " } ?? ""
        cells[column] = existingText + piece.text
    }
    return cells
}

// MARK: - Итоги и строки

private func readTotals(totalsLine: TextLine, boundariesX: [Double]) throws -> StatementTotals {
    let cells = makeCells(line: totalsLine, boundariesX: boundariesX)
    return StatementTotals(
        income: try parseAmount(cells[.income] ?? ""),
        expense: try parseAmount(cells[.expense] ?? ""),
        fee: try parseAmount(cells[.fee] ?? "")
    )
}

private func readRows(tableLines: [TextLine], boundariesX: [Double]) throws -> [StatementRow] {
    var rows: [StatementRow] = []
    for line in tableLines {
        guard !isTableHeaderLine(line), !isTotalsLine(line) else { continue }
        let cells = makeCells(line: line, boundariesX: boundariesX)

        guard isRowStart(cells: cells) else {
            // Описание переносится на следующие строки, иногда за разрыв страницы.
            // Подвал страницы («Выписка по счету: …») в колонку описания не попадает и сюда не доходит.
            guard let continuationText = cells[.description], let lastRow = rows.popLast() else { continue }
            rows.append(makeRowWithContinuation(lastRow, continuationText: continuationText))
            continue
        }
        rows.append(try makeRow(cells: cells))
    }
    return rows
}

private func isRowStart(cells: [StatementColumn: String]) -> Bool {
    guard let operationDayText = cells[.operationDay] else { return false }
    return operationDayText.range(of: #"^\d{2}\.\d{2}\.\d{4}$"#, options: .regularExpression) != nil
}

private func makeRow(cells: [StatementColumn: String]) throws -> StatementRow {
    StatementRow(
        operationDay: try parseDay(cells[.operationDay] ?? ""),
        processingDay: try parseDay(cells[.processingDay] ?? ""),
        description: cells[.description] ?? "",
        operationAmount: try parseAmount(cells[.operationAmount] ?? ""),
        // У служебных строк (ежемесячная комиссия) валюты операции нет.
        currency: cells[.currency] ?? "",
        incomeAmount: try parseAmount(cells[.income] ?? ""),
        expenseAmount: try parseAmount(cells[.expense] ?? ""),
        feeAmount: try parseAmount(cells[.fee] ?? ""),
        cardOrAccount: cells[.cardOrAccount] ?? ""
    )
}

private func makeRowWithContinuation(_ row: StatementRow, continuationText: String) -> StatementRow {
    StatementRow(
        operationDay: row.operationDay,
        processingDay: row.processingDay,
        description: row.description + " " + continuationText,
        operationAmount: row.operationAmount,
        currency: row.currency,
        incomeAmount: row.incomeAmount,
        expenseAmount: row.expenseAmount,
        feeAmount: row.feeAmount,
        cardOrAccount: row.cardOrAccount
    )
}

private func parseDay(_ text: String) throws -> CalendarDay {
    guard let day = CalendarDay(dotted: text) else {
        throw ParsingError.badDate(text)
    }
    return day
}

// MARK: - Шапка выписки

private func readHeader(preambleLines: [TextLine], totals: StatementTotals, sameColumnToleranceX: Double) throws -> StatementHeader {
    let headerTexts = makeHeaderTexts(preambleLines: preambleLines, sameColumnToleranceX: sameColumnToleranceX)
    guard let accountNumber = findTextAfterLabel("Номер счета:", in: headerTexts),
          let accountType = findTextAfterLabel("Тип счета:", in: headerTexts),
          let periodText = findTextAfterLabel("Период выписки:", in: headerTexts),
          let generatedOnText = findTextAfterLabel("Дата формирования выписки:", in: headerTexts),
          let openingBalanceText = findTextAfterLabel("Входящий остаток:", in: headerTexts),
          let closingBalanceText = findTextAfterLabel("Исходящий остаток:", in: headerTexts)
    else {
        throw StatementError.notHalykStatement
    }

    // «с 02.10.2025 по 09.10.2026»
    let periodDayTexts = periodText
        .split(separator: " ")
        .map { word in String(word) }
        .filter { word in word.range(of: #"^\d{2}\.\d{2}\.\d{4}$"#, options: .regularExpression) != nil }
    guard periodDayTexts.count == 2 else {
        throw ParsingError.badDate(periodText)
    }

    // Метка доступной суммы длинная и банк переносит её на вторую строку.
    let availableAmountText = findTextAfterLabel(
        "Доступная сумма с учетом кредитного лимита на дату формирования выписки:",
        in: headerTexts
    )
    let availableAmount = try availableAmountText.map { text in try parseAmount(text) }

    return StatementHeader(
        accountNumber: accountNumber,
        accountType: accountType,
        periodStart: try parseDay(periodDayTexts[0]),
        periodEnd: try parseDay(periodDayTexts[1]),
        generatedOn: try parseDay(generatedOnText),
        openingBalance: try parseAmount(openingBalanceText),
        closingBalance: try parseAmount(closingBalanceText),
        availableAmount: availableAmount,
        totals: totals
    )
}

/// Тексты шапки для поиска меток: сначала каждый кусок отдельно,
/// потом кусок вместе с куском под ним в той же колонке — для меток, перенесённых на две строки.
private func makeHeaderTexts(preambleLines: [TextLine], sameColumnToleranceX: Double) -> [String] {
    let singleTexts = preambleLines.flatMap { line in line.pieces.map { piece in piece.text } }

    var joinedTexts: [String] = []
    for (line, nextLine) in zip(preambleLines, preambleLines.dropFirst()) {
        for piece in line.pieces {
            guard let pieceBelow = nextLine.pieces.first(where: { below in abs(below.x - piece.x) <= sameColumnToleranceX }) else { continue }
            joinedTexts.append(piece.text + " " + pieceBelow.text)
        }
    }
    return singleTexts + joinedTexts
}

/// Первый текст, который начинается с метки; возвращает то, что после неё.
private func findTextAfterLabel(_ label: String, in texts: [String]) -> String? {
    for text in texts {
        guard let value = findTextAfterLabel(label, in: text) else { continue }
        return value
    }
    return nil
}

// PDF теряет пробелы внутри слов («Номерсчета:KZ…»), поэтому метку сравниваем через normalizeDescription,
// а значение берём из исходного текста, чтобы в нём сохранились пробелы.
private func findTextAfterLabel(_ label: String, in text: String) -> String? {
    let labelCharacters = Array(normalizeDescription(label))
    var matchedCount = 0
    var index = text.startIndex
    while matchedCount < labelCharacters.count {
        guard index < text.endIndex else { return nil }
        let character = text[index]
        index = text.index(after: index)
        guard !character.isWhitespace else { continue }
        guard normalizeDescription(String(character)) == String(labelCharacters[matchedCount]) else { return nil }
        matchedCount += 1
    }
    return text[index...].trimmingCharacters(in: .whitespaces)
}
