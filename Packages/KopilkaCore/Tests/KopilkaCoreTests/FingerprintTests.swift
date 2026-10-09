import Testing
@testable import KopilkaCore

func makeTestRow(
    description: String = "Зачисление с депозита",
    processingDay: CalendarDay = CalendarDay(year: 2026, month: 8, day: 12)
) -> StatementRow {
    StatementRow(
        operationDay: CalendarDay(year: 2026, month: 8, day: 11),
        processingDay: processingDay,
        description: description,
        operationAmount: 10000,
        currency: "KZT",
        incomeAmount: 10000,
        expenseAmount: 0,
        feeAmount: 0,
        cardOrAccount: "*3436"
    )
}

struct FingerprintTests {
    @Test func processingDayDoesNotChangeKey() {
        let first = makeTestRow(processingDay: CalendarDay(year: 2026, month: 8, day: 12))
        let second = makeTestRow(processingDay: CalendarDay(year: 2026, month: 8, day: 14))
        #expect(makeBaseKey(row: first, accountNumber: "KZ1") == makeBaseKey(row: second, accountNumber: "KZ1"))
    }

    @Test func whitespaceInDescriptionDoesNotChangeKey() {
        let spaced = makeTestRow(description: "Зачисление с\nдепозита")
        let compact = makeTestRow(description: "Зачислениесдепозита")
        #expect(makeBaseKey(row: spaced, accountNumber: "KZ1") == makeBaseKey(row: compact, accountNumber: "KZ1"))
    }

    @Test func accountNumberChangesKey() {
        let row = makeTestRow()
        #expect(makeBaseKey(row: row, accountNumber: "KZ1") != makeBaseKey(row: row, accountNumber: "KZ2"))
    }

    @Test func keyIsSha256Hex() {
        let key = makeBaseKey(row: makeTestRow(), accountNumber: "KZ1")
        #expect(key.count == 64)
    }

    @Test func identicalRowsGetNumberedKeysFromOne() {
        let rows = [makeTestRow(), makeTestRow(), makeTestRow()]
        let keys = makeKeyedRows(rows: rows, accountNumber: "KZ1").map { keyed in keyed.key }
        let base = makeBaseKey(row: rows[0], accountNumber: "KZ1")
        #expect(keys == ["\(base)#1", "\(base)#2", "\(base)#3"])
    }
}
