import Testing
@testable import KopilkaCore

@Suite struct ClassifierTests {
    @Test func builtInRuleFindsCategory() {
        let rules = makeBuiltInMerchantRules()
        #expect(findCategoryId(merchantKey: "MAGNUM", rules: rules) == "groceries")
        #expect(findCategoryId(merchantKey: "ЖИЛСТРОЙСБЕРБАНК", rules: rules) == "mortgage")
        #expect(findCategoryId(merchantKey: "ҚАЗАҚТЕЛЕКОМ", rules: rules) == "utilities")
        #expect(findCategoryId(merchantKey: "ОПЛАТАВМАРКЕТЕ", rules: rules) == "marketplaces")
        #expect(findCategoryId(merchantKey: "REGULARCHARGE", rules: rules) == "bankFees")
    }

    @Test func userRuleWinsOverBuiltIn() {
        let userRule = MerchantRule(merchantKey: "MAGNUM", categoryId: "cafes")
        let rules = makeBuiltInMerchantRules() + [userRule]
        #expect(findCategoryId(merchantKey: "MAGNUM", rules: rules) == "cafes")
    }

    @Test func longestUserFragmentWins() {
        let rules = makeBuiltInMerchantRules() + [
            MerchantRule(merchantKey: "MAGNUM", categoryId: "home"),
            MerchantRule(merchantKey: "MAGNUMCASHCARRY", categoryId: "cafes"),
        ]
        #expect(findCategoryId(merchantKey: "MAGNUMCASHCARRY", rules: rules) == "cafes")
    }

    @Test func longestBuiltInFragmentWins() {
        let rules = [
            MerchantRule(merchantKey: "YANDEX", categoryId: "home", isBuiltIn: true),
            MerchantRule(merchantKey: "YANDEXEDA", categoryId: "foodDelivery", isBuiltIn: true),
        ]
        #expect(findCategoryId(merchantKey: "YANDEXEDA", rules: rules) == "foodDelivery")
    }

    @Test func unknownMerchantReturnsNil() {
        #expect(findCategoryId(merchantKey: "IPAYUB", rules: makeBuiltInMerchantRules()) == nil)
    }

    @Test func builtInCategoriesAreUniqueAndComplete() {
        let categories = makeBuiltInCategories()
        let ids = categories.map { category in category.id }
        #expect(Set(ids).count == ids.count)
        #expect(ids.count == 28)
        #expect(categories.allSatisfy { category in category.monthlyLimit == nil })
    }

    @Test func builtInRulesPointToExistingCategories() {
        let ids = Set(makeBuiltInCategories().map { category in category.id })
        let rules = makeBuiltInMerchantRules()
        #expect(rules.allSatisfy { rule in rule.isBuiltIn && ids.contains(rule.categoryId) })
        #expect(rules.allSatisfy { rule in rule.merchantKey == makeMerchantKey(rule.merchantKey) })
    }
}
