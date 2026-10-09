import SwiftData

/// Все модели хранилища перечислены только здесь.
public func makeModelContainer(inMemory: Bool) throws -> ModelContainer {
    let schema = Schema([
        JournalEntry.self,
        SourceRecord.self,
        Account.self,
        SpendingCategory.self,
        MerchantRule.self,
        AmountRule.self,
        AppSettings.self,
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
    return try ModelContainer(for: schema, configurations: [configuration])
}
