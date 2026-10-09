import Testing
@testable import KopilkaCore

@Suite struct MerchantKeyTests {
    @Test func stripsBranchAndCashDeskTails() {
        #expect(makeMerchantKey("MAGNUM.ASF36.") == "MAGNUM")
        #expect(makeMerchantKey("MAGNUM.NSF72.KASSA- 1.") == "MAGNUM")
    }

    @Test func stripsSeparatorsAndDigits() {
        #expect(makeMerchantKey("FFT*PINDUODUO10") == "FFTPINDUODUO")
        #expect(makeMerchantKey("OPENAI *CHATGPTSUBSCR") == "OPENAICHATGPTSUBSCR")
    }

    @Test func keepsCyrillic() {
        #expect(makeMerchantKey("Жилстрой Сбербанк") == "ЖИЛСТРОЙСБЕРБАНК")
    }

    @Test func makesReadableTitle() {
        #expect(makeTitle(merchant: "MAGNUM.ASF36.") == "Magnum")
        #expect(makeTitle(merchant: "MAGNUM.NSF72.KASSA- 1.") == "Magnum")
        #expect(makeTitle(merchant: "OPENAI *CHATGPTSUBSCR") == "Openai Chatgptsubscr")
    }
}
