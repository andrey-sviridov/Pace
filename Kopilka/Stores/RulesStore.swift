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
}
