import Foundation
import Observation
import SwiftData
import KopilkaCore

/// Настройки приложения: одна запись `AppSettings` в базе. Экраны меняют её поля напрямую и вызывают `save()`.
@Observable
final class SettingsStore {
    private(set) var settings: AppSettings
    private let context: ModelContext

    init(context: ModelContext) throws {
        self.context = context
        self.settings = try findOrCreateSettings(context: context)
    }

    func save() throws {
        try context.save()
    }

    /// После «Начать заново» и восстановления копии старая запись настроек удалена — берём (или создаём) новую.
    func reloadSettings() throws {
        settings = try findOrCreateSettings(context: context)
    }

    /// Одна настройка — одно поле. Не сохранилось — возвращаем прежнее значение, как в updatePeriodMode.
    func update<Value>(_ field: ReferenceWritableKeyPath<AppSettings, Value>, to value: Value) throws {
        let previousValue = settings[keyPath: field]
        settings[keyPath: field] = value
        do {
            try context.save()
        } catch {
            settings[keyPath: field] = previousValue
            throw error
        }
    }

    /// Не сохранилось — возвращаем прежний режим, иначе экран показывал бы режим, которого нет в базе.
    func updatePeriodMode(_ mode: PeriodMode) throws {
        let previousMode = settings.periodMode
        settings.periodMode = mode
        do {
            try context.save()
        } catch {
            settings.periodMode = previousMode
            throw error
        }
    }

    func updateSavingsGoal(_ monthlyAmount: Decimal) throws {
        let previousGoal = settings.monthlySavingsGoal
        settings.monthlySavingsGoal = monthlyAmount
        do {
            try context.save()
        } catch {
            settings.monthlySavingsGoal = previousGoal
            throw error
        }
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
