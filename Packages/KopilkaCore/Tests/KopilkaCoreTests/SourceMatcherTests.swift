import Foundation
import SwiftData
import Testing
@testable import KopilkaCore

@Suite struct SourceMatcherTests {
    private let noon = Date(timeIntervalSince1970: 1_800_000_000)
    private let day = CalendarDay(dotted: "11.08.2026")!

    private func makeEntry(
        sources: [SourceKind],
        time: Date? = nil,
        day: CalendarDay? = nil,
        amount: Decimal = 1500,
        merchantKey: String = "MAGNUM",
        createdAt: Date = Date(timeIntervalSince1970: 1)
    ) -> JournalEntry {
        let entry = JournalEntry(
            day: day ?? self.day, time: time, type: .expense, amount: amount,
            title: "Покупка", merchantKey: merchantKey, createdAt: createdAt
        )
        entry.sources = sources.enumerated().map { index, kind in
            SourceRecord(kind: kind, key: "\(UUID())-\(index)", receivedAt: createdAt)
        }
        return entry
    }

    private func makeIncoming(
        _ kind: SourceKind,
        time: Date? = nil,
        day: CalendarDay? = nil,
        type: EntryType = .expense,
        amount: Decimal = 1500,
        merchantKey: String = "MAGNUM"
    ) -> IncomingOperation {
        IncomingOperation(kind: kind, day: day ?? self.day, time: time, type: type, amount: amount, merchantKey: merchantKey)
    }

    private func match(_ incoming: IncomingOperation, _ candidates: [JournalEntry]) -> MatchResult {
        findMatchingEntry(for: incoming, candidates: candidates, realtimeWindowMinutes: 10, statementWindowDays: 3)
    }

    @Test func smsThreeMinutesAfterApplePayAttaches() {
        let applePay = makeEntry(sources: [.applePay], time: noon)

        let result = match(makeIncoming(.sms, time: noon.addingTimeInterval(3 * 60)), [applePay])

        guard case .attach(let entry) = result else { Issue.record("ожидали attach"); return }
        #expect(entry === applePay)
    }

    @Test func smsFifteenMinutesAfterApplePayDoesNotMatch() {
        let applePay = makeEntry(sources: [.applePay], time: noon)

        let result = match(makeIncoming(.sms, time: noon.addingTimeInterval(15 * 60)), [applePay])

        guard case .noMatch = result else { Issue.record("ожидали noMatch"); return }
    }

    @Test func statementTwoDaysLaterAttachesButFourDaysDoesNot() {
        let applePay = makeEntry(sources: [.applePay], time: noon)

        let twoDays = match(makeIncoming(.statement, day: day.adding(days: 2)), [applePay])
        let fourDays = match(makeIncoming(.statement, day: day.adding(days: 4)), [applePay])

        guard case .attach = twoDays else { Issue.record("через 2 дня ожидали attach"); return }
        guard case .noMatch = fourDays else { Issue.record("через 4 дня ожидали noMatch"); return }
    }

    @Test func applePayDoesNotAttachToEarlierStatementRow() {
        // Ежедневный кофе: строка выписки за 09.08 уже есть, оплата 11.08 — это новая покупка, а не та же.
        let statementCoffee = makeEntry(sources: [.statement], day: day.adding(days: -2))

        let result = match(makeIncoming(.applePay, time: noon, day: day), [statementCoffee])

        guard case .noMatch = result else { Issue.record("оплата позже строки выписки не должна склеиться"); return }
    }

    @Test func statementRowDoesNotAttachToLaterApplePay() {
        let applePay = makeEntry(sources: [.applePay], time: noon, day: day)

        let result = match(makeIncoming(.statement, day: day.adding(days: -1)), [applePay])

        guard case .noMatch = result else { Issue.record("строка выписки раньше оплаты — другая операция"); return }
    }

    @Test func mergeWithDifferentAmountKeepsStatementAmount() throws {
        // Apple Pay 1 500, а в выписке 1 650 (чаевые): после склейки остаётся сумма выписки.
        let applePay = makeEntry(sources: [.applePay], time: noon, amount: 1500)
        let statement = makeEntry(sources: [.statement], amount: 1650)

        try mergeEntries(keep: applePay, remove: statement, allEntries: [applePay, statement])

        #expect(applePay.amount == 1650)
    }

    @Test func candidateWithSameSourceKindIsSkipped() {
        let alreadyHasSms = makeEntry(sources: [.sms], time: noon)

        let result = match(makeIncoming(.sms, time: noon.addingTimeInterval(60)), [alreadyHasSms])

        guard case .noMatch = result else { Issue.record("ожидали noMatch"); return }
    }

    @Test func twoCoffeesPickTheNearestInTime() {
        let morning = makeEntry(sources: [.applePay], time: noon.addingTimeInterval(-6 * 3600))
        let afternoon = makeEntry(sources: [.applePay], time: noon)

        let result = match(makeIncoming(.sms, time: noon.addingTimeInterval(2 * 60)), [morning, afternoon])

        guard case .attach(let entry) = result else { Issue.record("ожидали attach"); return }
        #expect(entry === afternoon)
    }

    @Test func differentMerchantWithSameAmountAndTimeIsPossibleDuplicate() {
        let applePay = makeEntry(sources: [.applePay], time: noon, merchantKey: "MAGNUM")

        let result = match(makeIncoming(.sms, time: noon.addingTimeInterval(60), merchantKey: "ARBUZ"), [applePay])

        guard case .possibleDuplicate(let entry) = result else { Issue.record("ожидали possibleDuplicate"); return }
        #expect(entry === applePay)
    }

    @Test func incomeDoesNotMatchExpenseOfSameAmount() {
        let purchase = makeEntry(sources: [.applePay], time: noon)

        let result = match(makeIncoming(.statement, type: .income), [purchase])

        guard case .noMatch = result else { Issue.record("ожидали noMatch"); return }
    }

    @Test func differentAmountDoesNotMatch() {
        let applePay = makeEntry(sources: [.applePay], time: noon)

        let result = match(makeIncoming(.sms, time: noon, amount: 1501), [applePay])

        guard case .noMatch = result else { Issue.record("ожидали noMatch"); return }
    }

    @Test func emptyMerchantIsCompatibleWithAny() {
        let transfer = makeEntry(sources: [.applePay], time: noon, merchantKey: "")

        let result = match(makeIncoming(.sms, time: noon, merchantKey: "ARBUZ"), [transfer])

        guard case .attach = result else { Issue.record("ожидали attach"); return }
    }

    @Test func mergedEntryIsNotACandidate() {
        let keep = makeEntry(sources: [.sms], time: noon)
        let hidden = makeEntry(sources: [.applePay], time: noon)
        hidden.mergedInto = keep

        let result = match(makeIncoming(.statement), [hidden])

        guard case .noMatch = result else { Issue.record("ожидали noMatch"); return }
    }

    @Test func equalDistanceTakesEarlierCreatedEntry() {
        let older = makeEntry(sources: [.applePay], time: noon, createdAt: Date(timeIntervalSince1970: 10))
        let newer = makeEntry(sources: [.applePay], time: noon, createdAt: Date(timeIntervalSince1970: 20))

        let result = match(makeIncoming(.sms, time: noon), [newer, older])

        guard case .attach(let entry) = result else { Issue.record("ожидали attach"); return }
        #expect(entry === older)
    }

    @Test func mergeMovesAllSourcesAndHidesRemovedEntry() throws {
        let context = ModelContext(try makeModelContainer(inMemory: true))
        let keep = makeEntry(sources: [.applePay], time: noon)
        let remove = makeEntry(sources: [.sms, .statement], time: noon)
        context.insert(keep)
        context.insert(remove)
        keep.possibleDuplicateOf = remove

        try mergeEntries(keep: keep, remove: remove, allEntries: [keep, remove])
        try context.save()

        #expect(keep.sources.count == 3)
        #expect(remove.sources.isEmpty)
        #expect(remove.mergedInto === keep)
        #expect(keep.possibleDuplicateOf == nil)
    }

    @Test func mergeCarriesFeeWhenKeptEntryHasNone() throws {
        let keep = makeEntry(sources: [.sms], time: noon)
        let remove = makeEntry(sources: [.statement])
        remove.feeAmount = 200

        try mergeEntries(keep: keep, remove: remove, allEntries: [keep, remove])

        #expect(keep.feeAmount == 200)
    }

    @Test func mergeKeepsExistingFee() throws {
        let keep = makeEntry(sources: [.statement])
        keep.feeAmount = 150
        let remove = makeEntry(sources: [.sms], time: noon)
        remove.feeAmount = 200

        try mergeEntries(keep: keep, remove: remove, allEntries: [keep, remove])

        #expect(keep.feeAmount == 150)
    }

    @Test func mergeRedirectsChainToKeptEntry() throws {
        let first = makeEntry(sources: [.applePay], time: noon)
        let second = makeEntry(sources: [.sms], time: noon)
        let third = makeEntry(sources: [.statement])
        let allEntries = [first, second, third]

        // X склеили в Y, потом Y склеили в Z: X должна указывать на Z, а не на скрытую Y.
        try mergeEntries(keep: second, remove: first, allEntries: allEntries)
        try mergeEntries(keep: third, remove: second, allEntries: allEntries)

        #expect(first.mergedInto === third)
        #expect(second.mergedInto === third)
        #expect(third.mergedInto == nil)
        #expect(findMergeRoot(first) === third)
        #expect(findMergeRoot(third) === third)
    }

    @Test func mergeRejectsSameOrHiddenEntry() throws {
        let keep = makeEntry(sources: [.applePay], time: noon)
        let remove = makeEntry(sources: [.sms], time: noon)
        let other = makeEntry(sources: [.statement])

        #expect(throws: MergeError.sameEntry) {
            try mergeEntries(keep: keep, remove: keep, allEntries: [keep])
        }
        try mergeEntries(keep: keep, remove: remove, allEntries: [keep, remove])
        #expect(throws: MergeError.entryAlreadyMerged) {
            try mergeEntries(keep: remove, remove: other, allEntries: [keep, remove, other])
        }
        #expect(throws: MergeError.entryAlreadyMerged) {
            try mergeEntries(keep: other, remove: remove, allEntries: [keep, remove, other])
        }
    }
}
