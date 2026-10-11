import Foundation
import Observation
import SwiftData
import PaceCore

/// Категории и правила (продавцов и сумм).
@Observable
final class RulesStore {
    private let context: ModelContext

    init(context: ModelContext) throws {
        self.context = context
        try deleteDateRuleLeftover()
    }

    /// Раньше было правило «все переводы до 1 марта — на свою Kaspi». Поле с датой из базы ушло,
    /// и от правила осталась пустышка с суммой 0 ₸: редактор такую создать не даёт, поэтому узнаём её по сумме.
    private func deleteDateRuleLeftover() throws {
        let rules = try context.fetch(FetchDescriptor<AmountRule>())
        let leftoverRules = rules.filter { rule in rule.maxAmount == 0 }
        guard !leftoverRules.isEmpty else { return }
        for rule in leftoverRules {
            context.delete(rule)
        }
        try context.save()
    }

    /// Добавляет только то, чего нет: категории — по id, правила продавцов — по ключу, правила сумм — если таблица пуста.
    /// Существующие записи не трогаем: SwiftData при совпадении уникального поля молча перезаписал бы
    /// правку пользователя встроенным значением.
    func seedBuiltInsIfMissing() throws {
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
        let missingAmountRules = amountRuleCount == 0 ? makeDefaultAmountRules() : []
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

    /// Встроенные тоже можно удалять: засев идёт только при начальной настройке, поэтому правило
    /// вернётся лишь после «Начать заново». Уже размеченные записи удаление не трогает.
    func deleteMerchantRule(_ rule: MerchantRule) throws {
        context.delete(rule)
        try context.save()
    }

    // MARK: Правила сумм

    /// Новое правило встаёт в конец: при совпадении нескольких правил срабатывает первое по порядку.
    func addAmountRule(_ draft: AmountRuleDraft) throws {
        let rules = try context.fetch(FetchDescriptor<AmountRule>())
        let lastSortOrder = rules.map { rule in rule.sortOrder }.max() ?? 0
        let rule = AmountRule(minAmount: draft.minAmount, maxAmount: draft.maxAmount, sortOrder: lastSortOrder + 1)
        applyDraft(draft, to: rule)
        context.insert(rule)
        try context.save()
    }

    func updateAmountRule(_ rule: AmountRule, with draft: AmountRuleDraft) throws {
        applyDraft(draft, to: rule)
        try context.save()
    }

    func deleteAmountRule(_ rule: AmountRule) throws {
        context.delete(rule)
        try context.save()
    }

    /// «Перевод на свою карту» — не категория, а счёт: импорт тогда делает из перевода перемещение.
    private func applyDraft(_ draft: AmountRuleDraft, to rule: AmountRule) {
        rule.minAmount = draft.minAmount
        rule.maxAmount = draft.maxAmount
        rule.afterEvent = draft.afterEvent
        rule.windowDays = draft.windowDays
        let isOwnCardTransfer = draft.categoryId == "ownTransfer"
        rule.categoryId = isOwnCardTransfer ? nil : draft.categoryId
        rule.targetAccountKind = isOwnCardTransfer ? .ownOtherCard : nil
    }
}

/// То, что пользователь вводит на экране правила сумм.
struct AmountRuleDraft {
    var minAmount: Decimal
    var maxAmount: Decimal
    var afterEvent: SalaryEventKind?
    var windowDays: Int
    var categoryId: String
}
