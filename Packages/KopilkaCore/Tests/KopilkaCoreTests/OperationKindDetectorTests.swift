import Testing
@testable import KopilkaCore

@Suite struct OperationKindDetectorTests {
    @Test func detectsPurchaseWithMerchantKeepingSpaces() {
        let kind = detectOperationKind(description: "Операцияоплатыу коммерсантаOPENAI *CHATGPTSUBSCR")
        #expect(kind == .purchase(merchant: "OPENAI *CHATGPTSUBSCR"))
    }

    @Test func detectsSalaryWithEmployer() {
        let kind = detectOperationKind(description: "ПоступлениенасчетТОО \"АЦЭПАК\"")
        #expect(kind == .salary(employer: "АЦЭПАК"))
    }

    @Test func detectsTransferToOtherCard() {
        #expect(detectOperationKind(description: "Переводнадругуюкарту") == .transferToOtherCard)
    }

    @Test func detectsDepositMovements() {
        #expect(detectOperationKind(description: "Переводнадепозит") == .toDeposit)
        #expect(detectOperationKind(description: "Зачислениесдепозита") == .fromDeposit)
    }

    @Test func detectsIncomingTransfers() {
        #expect(detectOperationKind(description: "Поступлениеперевода") == .incomingTransfer)
        let paymentFromAccount = "Платежстекущегосчета ONLBнаФЛ PHONE_NUMBER безвозмездныепереводы"
        #expect(detectOperationKind(description: paymentFromAccount) == .incomingTransfer)
    }

    @Test func detectsRefundWithMerchant() {
        let kind = detectOperationKind(description: "Поступлениенакарту YANDEX.EDA")
        #expect(kind == .refund(merchant: "YANDEX.EDA"))
    }

    @Test func detectsLoanPayments() {
        #expect(detectOperationKind(description: "Погашениебанковской задолженности") == .loanPayment)
        #expect(detectOperationKind(description: "ПереводнакредитRS Погашениекредита") == .loanPayment)
    }

    @Test func mortgageWinsOverPurchase() {
        let kind = detectOperationKind(description: "Операцияоплатыу коммерсантаОплата кредитав ЖилстройСберБанке")
        #expect(kind == .mortgagePayment)
    }

    @Test func detectsInternationalTransfer() {
        #expect(detectOperationKind(description: "Исходящий международныйперевод кбк...") == .internationalTransfer)
    }

    @Test func detectsMonthlyFee() {
        #expect(detectOperationKind(description: "Ежемесячнаякомиссияза обслуживаниекарточки RegularCharge") == .monthlyFee)
    }

    @Test func detectsDepositInterest() {
        #expect(detectOperationKind(description: "Выплата вознаграждения по депозиту") == .depositInterest)
        #expect(detectOperationKind(description: "Капитализация") == .depositInterest)
    }

    @Test func returnsUnknownForOtherText() {
        #expect(detectOperationKind(description: "Что-то новое") == .unknown)
    }
}
