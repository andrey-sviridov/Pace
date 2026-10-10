import Foundation
import SwiftData
import Testing
@testable import KopilkaCore

@Suite struct ModelsTests {
    @Test func savesEntryWithSources() throws {
        let container = try makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        let entry = JournalEntry(day: CalendarDay(year: 2026, month: 3, day: 5), type: .expense, amount: Decimal(string: "347.09")!, title: "Магнум")
        entry.sources = [
            SourceRecord(kind: .statement, key: "a", receivedAt: Date(timeIntervalSince1970: 0)),
            SourceRecord(kind: .sms, key: "b", receivedAt: Date(timeIntervalSince1970: 10), rawText: "Покупка 347.09 KZT"),
        ]
        context.insert(entry)
        try context.save()

        let fetched = try ModelContext(container).fetch(FetchDescriptor<JournalEntry>())
        #expect(fetched.count == 1)
        #expect(fetched[0].amount == Decimal(string: "347.09")!)
        #expect(fetched[0].day == CalendarDay(year: 2026, month: 3, day: 5))
        #expect(fetched[0].sources.count == 2)
        #expect(fetched[0].sources.allSatisfy { source in source.entry?.id == entry.id })
    }

    @Test func duplicateSourceKeyUpsertsIntoSingleRecord() throws {
        let container = try makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        let receivedAt = Date(timeIntervalSince1970: 0)
        let entry = JournalEntry(day: CalendarDay(year: 2026, month: 3, day: 5), type: .expense, amount: 100, title: "Магнум")
        entry.sources = [SourceRecord(kind: .statement, key: "same", receivedAt: receivedAt, rawDescription: "первая")]
        context.insert(entry)
        try context.save()

        context.insert(SourceRecord(kind: .statement, key: "same", receivedAt: receivedAt, rawDescription: "вторая"))
        try context.save()

        // Почему: SwiftData не бросает ошибку, а заменяет поля старой записи и отвязывает её от записи журнала,
        // поэтому импорт обязан пропускать известные ключи до вставки.
        let records = try context.fetch(FetchDescriptor<SourceRecord>())
        #expect(records.count == 1)
        #expect(records[0].rawDescription == "вторая")
        #expect(records[0].entry == nil)
    }

    @Test func settingsHaveDefaults() throws {
        let settings = AppSettings()
        #expect(settings.theme == .light)
        #expect(settings.periodMode == .salaryMonth)
        #expect(settings.employerName == "АЦЭПАК")
        #expect(settings.kaspiOwnCardUntil == CalendarDay(year: 2026, month: 3, day: 1))
        #expect(!settings.isApplePayEnabled && !settings.isSmsEnabled)
        #expect(settings.monthlySavingsGoal == 0)
        #expect(!settings.hasFinishedSetup)
        #expect(settings.hasAdvance)
        #expect(settings.shouldShowOperationTime)
    }
}
