import Testing
@testable import KopilkaCore

struct TextNormalizingTests {
    @Test func removesWhitespaceAndUppercases() {
        #expect(normalizeDescription("Перевод на\nдругую карту") == "ПЕРЕВОДНАДРУГУЮКАРТУ")
    }
}
