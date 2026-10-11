import Foundation
import Testing
@testable import PaceCore

struct MoneyParsingTests {
    @Test func parsesNegativeAmountWithSpaceSeparator() throws {
        #expect(try parseAmount("-1 093,00") == -1093)
    }

    @Test func parsesLargeAmount() throws {
        #expect(try parseAmount("400 000,00") == 400000)
    }

    @Test func parsesZero() throws {
        #expect(try parseAmount("0,00") == 0)
    }

    @Test func parsesFraction() throws {
        #expect(try parseAmount("347,09") == Decimal(string: "347.09"))
    }

    @Test func parsesNonBreakingSpace() throws {
        #expect(try parseAmount("1\u{00A0}093,50") == Decimal(string: "1093.50"))
    }

    @Test func throwsOnGarbage() {
        #expect(throws: ParsingError.badAmount("abc")) {
            try parseAmount("abc")
        }
    }

    @Test(arguments: ["12abc", "-", "1,093.50", "", "1 093,00 KZT", "1e3", "5-"])
    func throwsOnJunk(text: String) {
        #expect(throws: ParsingError.badAmount(text)) {
            try parseAmount(text)
        }
    }
}
