import Foundation
import Testing
@testable import KopilkaCore

@Suite struct SalaryEventsTests {
    private func makeSalaryEntry(_ dotted: String, _ amountTenge: Decimal) -> JournalEntry {
        JournalEntry(
            day: CalendarDay(dotted: dotted)!,
            type: .income,
            amount: amountTenge,
            title: "Поступление на счет ТОО АЦЭПАК",
            categoryId: "salary"
        )
    }

    private func findEvents(_ entries: [JournalEntry]) -> [SalaryEvent] {
        findSalaryEvents(entries: entries, advanceDayRange: 10...20, oneOffAboveMedianTimes: 1.5)
    }

    @Test func kindIsDefinedByDayOfMonth() {
        let events = findEvents([makeSalaryEntry("15.01.2026", 400_000), makeSalaryEntry("30.01.2026", 410_000)])
        #expect(events.map { event in event.kind } == [.advance, .salary])
        #expect(events.allSatisfy { event in !event.isOneOff })
    }

    @Test func hugeIncomeIsOneOff() {
        let events = findEvents([
            makeSalaryEntry("30.01.2026", 400_000),
            makeSalaryEntry("15.02.2026", 410_000),
            makeSalaryEntry("27.02.2026", 1_122_406),
            makeSalaryEntry("15.03.2026", 405_000),
        ])
        let oneOff = events.first { event in event.day == CalendarDay(dotted: "27.02.2026")! }
        #expect(oneOff?.isOneOff == true)
        #expect(oneOff?.kind == .salary)
        #expect(events.filter { event in event.isOneOff }.count == 1)
    }

    @Test func ignoresNonSalaryAndMergedEntries() {
        let other = JournalEntry(day: CalendarDay(dotted: "15.01.2026")!, type: .income, amount: 5000, title: "x", categoryId: "incomingTransfers")
        let expense = JournalEntry(day: CalendarDay(dotted: "15.01.2026")!, type: .expense, amount: 5000, title: "x", categoryId: "salary")
        let merged = makeSalaryEntry("15.01.2026", 400_000)
        merged.mergedInto = makeSalaryEntry("15.01.2026", 400_000)
        #expect(findEvents([other, expense, merged]).isEmpty)
    }

    @Test func predictsMedianOfLastThree() {
        let history = [
            SalaryEvent(day: CalendarDay(dotted: "15.06.2026")!, amount: 100, kind: .advance, isOneOff: false),
            SalaryEvent(day: CalendarDay(dotted: "15.07.2026")!, amount: 402_487, kind: .advance, isOneOff: false),
            SalaryEvent(day: CalendarDay(dotted: "15.08.2026")!, amount: 400_000, kind: .advance, isOneOff: false),
            SalaryEvent(day: CalendarDay(dotted: "15.09.2026")!, amount: 410_000, kind: .advance, isOneOff: false),
            SalaryEvent(day: CalendarDay(dotted: "30.09.2026")!, amount: 999, kind: .salary, isOneOff: false),
        ]
        let predicted = predictNextEvent(kind: .advance, after: CalendarDay(dotted: "15.09.2026")!, history: history, lookbackCount: 3)
        #expect(predicted?.amount == 402_487)
        #expect(predicted?.day == CalendarDay(dotted: "15.10.2026")!)
        #expect(predicted?.kind == .advance)
    }

    @Test func predictionSkipsOneOffsAndEmptyHistory() {
        let after = CalendarDay(dotted: "01.10.2026")!
        #expect(predictNextEvent(kind: .salary, after: after, history: [], lookbackCount: 3) == nil)
        let oneOff = SalaryEvent(day: CalendarDay(dotted: "27.02.2026")!, amount: 1_122_406, kind: .salary, isOneOff: true)
        #expect(predictNextEvent(kind: .salary, after: after, history: [oneOff], lookbackCount: 3) == nil)
    }
}
