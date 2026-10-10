import Foundation
import Observation
import SwiftData
import KopilkaCore

/// Категории и правила (продавцов и сумм).
@Observable
final class RulesStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Добавляет только то, чего нет: категории — по id, правила продавцов — по ключу, правила сумм — если таблица пуста.
    /// Существующие записи не трогаем: SwiftData при совпадении уникального поля молча перезаписал бы
    /// правку пользователя встроенным значением.
    func seedBuiltInsIfMissing(kaspiOwnCardUntil: CalendarDay) throws {
        let existingCategories = try context.fetch(FetchDescriptor<SpendingCategory>())
        let existingCategoryIds = Set(existingCategories.map { category in category.id })
        let missingCategories = makeBuiltInCategories().filter { category in !existingCategoryIds.contains(category.id) }
        for category in missingCategories {
            context.insert(category)
        }

        let existingRules = try context.fetch(FetchDescriptor<MerchantRule>())
        let existingMerchantKeys = Set(existingRules.map { rule in rule.merchantKey })
        let missingRules = makeBuiltInMerchantRules().filter { rule in !existingMerchantKeys.contains(rule.merchantKey) }
        for rule in missingRules {
            context.insert(rule)
        }

        // Правила сумм не имеют ключа: если пользователь уже что-то настроил, стартовые не подмешиваем.
        let amountRuleCount = try context.fetchCount(FetchDescriptor<AmountRule>())
        let missingAmountRules = amountRuleCount == 0 ? makeDefaultAmountRules(kaspiOwnCardUntil: kaspiOwnCardUntil) : []
        for rule in missingAmountRules {
            context.insert(rule)
        }

        try context.save()
    }

    // MARK: - Лимиты и ожидаемые суммы
    // Не сохранилось — возвращаем прежнее значение, иначе экран показывал бы то, чего нет в базе.

    func updateMonthlyLimit(_ amount: Decimal, of category: SpendingCategory) throws {
        let previousLimit = category.monthlyLimit
        category.monthlyLimit = amount
        do {
            try context.save()
        } catch {
            category.monthlyLimit = previousLimit
            throw error
        }
    }

    func removeMonthlyLimit(of category: SpendingCategory) throws {
        let previousLimit = category.monthlyLimit
        category.monthlyLimit = nil
        do {
            try context.save()
        } catch {
            category.monthlyLimit = previousLimit
            throw error
        }
    }

    func updateExpectedAmount(_ amount: Decimal, of category: SpendingCategory) throws {
        let previousAmount = category.expectedMonthlyAmount
        category.expectedMonthlyAmount = amount
        do {
            try context.save()
        } catch {
            category.expectedMonthlyAmount = previousAmount
            throw error
        }
    }

    /// Без заданной суммы план обязательной считается по медиане последних месяцев.
    func resetExpectedAmount(of category: SpendingCategory) throws {
        let previousAmount = category.expectedMonthlyAmount
        category.expectedMonthlyAmount = nil
        do {
            try context.save()
        } catch {
            category.expectedMonthlyAmount = previousAmount
            throw error
        }
    }

    func updateWarnPercent(_ percent: Int, of category: SpendingCategory) throws {
        let previousPercent = category.warnAtPercent
        category.warnAtPercent = percent
        do {
            try context.save()
        } catch {
            category.warnAtPercent = previousPercent
            throw error
        }
    }

    // MARK: - Правила продавцов и сумм (экран «Правила»)

    /// Правка встроенного правила делает его правилом пользователя: засев его больше не трогает.
    func updateMerchantRule(_ rule: MerchantRule, categoryId: String) throws {
        rule.categoryId = categoryId
        rule.isBuiltIn = false
        try context.save()
    }

    /// Удалять можно только свои правила: встроенное всё равно вернулось бы при следующем засеве.
    func deleteMerchantRule(_ rule: MerchantRule) throws {
        guard !rule.isBuiltIn else { return }
        context.delete(rule)
        try context.save()
    }

    func updateAmountRange(_ rule: AmountRule, minAmount: Decimal, maxAmount: Decimal) throws {
        rule.minAmount = minAmount
        rule.maxAmount = maxAmount
        try context.save()
    }

    func updateWindowDays(_ rule: AmountRule, windowDays: Int) throws {
        rule.windowDays = windowDays
        try context.save()
    }

    /// Дата «переводы до … — на свою Kaspi» живёт в двух местах: в настройках и в правиле сумм с beforeDay.
    /// Меняем обе, иначе импорт продолжил бы считать по старой дате.
    func updateKaspiCutoff(_ day: CalendarDay) throws {
        let rules = try context.fetch(FetchDescriptor<AmountRule>())
        let cutoffRules = rules.filter { rule in rule.beforeDay != nil }
        for rule in cutoffRules {
            rule.beforeDay = day
        }
        try context.save()
    }
}
