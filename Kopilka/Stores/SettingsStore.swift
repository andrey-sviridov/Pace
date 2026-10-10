import Foundation
import Observation
import SwiftData
import KopilkaCore

/// Настройки приложения: одна запись `AppSettings` в базе. Экраны меняют её поля напрямую и вызывают `save()`.
@Observable
final class SettingsStore {
    let settings: AppSettings
    private let context: ModelContext

    init(context: ModelContext) throws {
        self.context = context
        self.settings = try findOrCreateSettings(context: context)
    }

    func save() throws {
        try context.save()
    }

    func updatePeriodMode(_ mode: PeriodMode) throws {
        settings.periodMode = mode
        try context.save()
    }

    /// Признак ставим только вместе с успешным сохранением: иначе экран ушёл бы на вкладки, а база осталась без настройки.
    func saveSetupFinished() throws {
        settings.hasFinishedSetup = true
        do {
            try context.save()
        } catch {
            settings.hasFinishedSetup = false
            throw error
        }
    }
}

/// Первый запуск — записи ещё нет, создаём со значениями по умолчанию и сразу сохраняем:
/// откат при ошибке импорта иначе стёр бы несохранённые настройки.
private func findOrCreateSettings(context: ModelContext) throws -> AppSettings {
    if let settings = try context.fetch(FetchDescriptor<AppSettings>()).first {
        return settings
    }
    let settings = AppSettings()
    context.insert(settings)
    try context.save()
    return settings
}
