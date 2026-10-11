import Foundation
import Testing
@testable import PaceCore

// Реальная выписка содержит личные данные и в git не попадает, поэтому без неё тест выключен.
struct StatementAcceptanceTests {
    @Test(.disabled(if: findRealStatementURL() == nil, "Нет Fixtures/halyk-2026.pdf"))
    func parsesRealStatement() throws {
        let fileURL = try #require(findRealStatementURL())
        let pdfData = try Data(contentsOf: fileURL)

        let lines = try readTextLines(pdfData: pdfData)
        let statement = try readStatement(lines: lines)

        let incomeSum = statement.rows.reduce(Decimal(0)) { sum, row in sum + row.incomeAmount }
        let expenseSum = statement.rows.reduce(Decimal(0)) { sum, row in sum + row.expenseAmount }
        let feeSum = statement.rows.reduce(Decimal(0)) { sum, row in sum + row.feeAmount }
        #expect(statement.rows.count == 1160)
        #expect(incomeSum == Decimal(string: "11341662.95"))
        #expect(expenseSum == Decimal(string: "-11321791.63"))
        #expect(feeSum == Decimal(string: "-9800.00"))
        #expect(statement.header.accountNumber == "KZ126010002008249310")
        #expect(statement.header.availableAmount == Decimal(string: "6933.41"))
        try checkTotals(statement)
    }
}

private func findRealStatementURL() -> URL? {
    Bundle.module.url(forResource: "halyk-2026", withExtension: "pdf", subdirectory: "Fixtures")
}
