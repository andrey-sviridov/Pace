import Foundation

/// Категория по ключу продавца: сначала правила пользователя, потом встроенные.
/// Внутри группы побеждает самый длинный подходящий фрагмент ("MAGNUMCASHCARRY" сильнее "MAGNUM").
public func findCategoryId(merchantKey: String, rules: [MerchantRule]) -> String? {
    let userRules = rules.filter { rule in !rule.isBuiltIn }
    let builtInRules = rules.filter { rule in rule.isBuiltIn }

    if let userRule = findLongestMatchingRule(merchantKey: merchantKey, rules: userRules) {
        return userRule.categoryId
    }
    return findLongestMatchingRule(merchantKey: merchantKey, rules: builtInRules)?.categoryId
}

private func findLongestMatchingRule(merchantKey: String, rules: [MerchantRule]) -> MerchantRule? {
    let matchingRules = rules.filter { rule in
        !rule.merchantKey.isEmpty && merchantKey.contains(rule.merchantKey)
    }
    return matchingRules.max { first, second in first.merchantKey.count < second.merchantKey.count }
}
