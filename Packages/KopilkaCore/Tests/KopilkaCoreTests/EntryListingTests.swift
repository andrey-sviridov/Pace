import Foundation
import Testing
@testable import KopilkaCore

@Suite struct EntryListingTests {
    private func makeEntry(_ dotted: String, amount: Decimal = 1500, createdAt: Double = 1, type: EntryType = .expense) -> JournalEntry {
        JournalEntry(
            day: makeDay(dotted), type: type, amount: amount,
            title: "Покупка", createdAt: Date(timeIntervalSince1970: createdAt)
        )
    }

    @Test func groupsByDayNewestFirst() {
        let older = makeEntry("10.10.2026")
        let newerFirst = makeEntry("12.10.2026", createdAt: 1)
        let newerSecond = makeEntry("12.10.2026", createdAt: 2)

        let groups = makeDayGroups([older, newerFirst, newerSecond])

        #expect(groups.map { group in group.day } == [makeDay("12.10.2026"), makeDay("10.10.2026")])
        #expect(groups[0].entries.map { entry in entry.createdAt } == [newerSecond.createdAt, newerFirst.createdAt])
        #expect(groups[1].entries.count == 1)
    }

    @Test func emptyEntriesGiveNoGroups() {
        #expect(makeDayGroups([]).isEmpty)
    }

    @Test func mergeCandidatesHaveSameTypeAndAmountWithinWindow() {
        let entry = makeEntry("12.10.2026", amount: 1500)
        let sameDay = makeEntry("12.10.2026", amount: 1500)
        let threeDaysLater = makeEntry("15.10.2026", amount: 1500)
        let fourDaysEarlier = makeEntry("08.10.2026", amount: 1500)
        let otherAmount = makeEntry("12.10.2026", amount: 1501)
        let otherType = makeEntry("12.10.2026", amount: 1500, type: .transfer)
        let merged = makeEntry("12.10.2026", amount: 1500)
        merged.mergedInto = sameDay

        let candidates = findMergeCandidates(
            for: entry,
            among: [entry, threeDaysLater, sameDay, fourDaysEarlier, otherAmount, otherType, merged],
            windowDays: 3
        )

        #expect(candidates.count == 2)
        #expect(candidates[0] === sameDay)
        #expect(candidates[1] === threeDaysLater)
    }

    @Test func signedAmountByType() {
        #expect(formatSignedTenge(1500, type: .expense) == "−1\u{00A0}500 ₸")
        #expect(formatSignedTenge(1500, type: .income) == "+1\u{00A0}500 ₸")
        #expect(formatSignedTenge(1500, type: .transfer) == "1\u{00A0}500 ₸")
    }

    @Test func dayHeaderHasWeekday() {
        #expect(formatDayWithWeekday(makeDay("12.10.2026")) == "12 окт, пн")
        #expect(formatDayWithWeekday(makeDay("01.03.2026")) == "1 мар, вс")
    }
}
