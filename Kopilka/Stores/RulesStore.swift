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
}
