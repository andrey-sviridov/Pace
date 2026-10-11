import Testing
@testable import PaceCore

struct TextNormalizingTests {
    @Test func removesWhitespaceAndUppercases() {
        #expect(normalizeDescription("Перевод на\nдругую карту") == "ПЕРЕВОДНАДРУГУЮКАРТУ")
    }
}
