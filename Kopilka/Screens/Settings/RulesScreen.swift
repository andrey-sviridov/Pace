import SwiftUI
import SwiftData
import KopilkaCore

/// «Правила»: продавец → категория и правила сумм для переводов без получателя (спека §5.3, §5.5).
/// Свои правила можно удалить, встроенные — только поправить (правка делает их своими).
struct RulesScreen: View {
    @Environment(\.theme) private var theme

    @Query(sort: \MerchantRule.merchantKey) private var merchantRules: [MerchantRule]
    @Query(sort: \AmountRule.sortOrder) private var amountRules: [AmountRule]
    @Query private var categories: [SpendingCategory]

    @State private var query = ""

    var body: some View {
        let namesById = makeCategoryNamesById(categories)
        let foundRules = merchantRules.filter { rule in
            query.isEmpty || rule.merchantKey.localizedCaseInsensitiveContains(query)
        }
        let userRules = foundRules.filter { rule in !rule.isBuiltIn }
        let builtInRules = foundRules.filter { rule in rule.isBuiltIn }

        List {
            Section("Переводы по сумме") {
                ForEach(amountRules) { rule in
                    NavigationLink {
                        AmountRuleScreen(rule: rule, categoryName: makeCategoryName(categoryId: rule.categoryId, namesById: namesById))
                    } label: {
                        AmountRuleRow(rule: rule, categoryName: makeCategoryName(categoryId: rule.categoryId, namesById: namesById))
                    }
                }
            }
            MerchantRulesSection(title: "Мои правила", rules: userRules, categories: categories, namesById: namesById)
            MerchantRulesSection(title: "Встроенные", rules: builtInRules, categories: categories, namesById: namesById)
        }
        .searchable(text: $query, prompt: "MAGNUM")
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .navigationTitle("Правила")
    }
}

private struct MerchantRulesSection: View {
    let title: String
    let rules: [MerchantRule]
    let categories: [SpendingCategory]
    let namesById: [String: String]

    @Environment(RulesStore.self) private var rulesStore
    @Environment(ErrorStore.self) private var errorStore

    @State private var editedRule: MerchantRule?

    var body: some View {
        if !rules.isEmpty {
            Section(title) {
                ForEach(rules) { rule in
                    Button { editedRule = rule } label: {
                        LabeledContent(rule.title ?? rule.merchantKey, value: makeCategoryName(categoryId: rule.categoryId, namesById: namesById))
                    }
                    .foregroundStyle(.primary)
                    .swipeActions {
                        if !rule.isBuiltIn {
                            Button("Удалить", role: .destructive) { delete(rule) }
                        }
                    }
                }
            }
            .sheet(item: $editedRule) { rule in
                CategoryPicker(categories: categories, selectedId: rule.categoryId) { categoryId in
                    update(rule, categoryId: categoryId)
                }
            }
        }
    }

    private func update(_ rule: MerchantRule, categoryId: String) {
        do {
            try rulesStore.updateMerchantRule(rule, categoryId: categoryId)
        } catch {
            errorStore.show(error)
        }
    }

    private func delete(_ rule: MerchantRule) {
        do {
            try rulesStore.deleteMerchantRule(rule)
        } catch {
            errorStore.show(error)
        }
    }
}

private struct AmountRuleRow: View {
    let rule: AmountRule
    let categoryName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(makeAmountRuleTitle(rule))
            Text(rule.targetAccountKind == .ownOtherCard ? "→ своя Kaspi" : "→ \(categoryName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Правка правила сумм: диапазон и окно в днях. Правило «до даты» правится в настройках (дата Kaspi).
private struct AmountRuleScreen: View {
    let rule: AmountRule
    let categoryName: String

    @Environment(RulesStore.self) private var rulesStore
    @Environment(ErrorStore.self) private var errorStore
    @Environment(\.theme) private var theme

    @State private var minAmount: Decimal?
    @State private var maxAmount: Decimal?

    var body: some View {
        Form {
            if rule.beforeDay != nil {
                Text("Все переводы на другую карту раньше этой даты считаются переводами на вашу Kaspi. Дата меняется в «Мои счета» → ваша Kaspi.")
            } else {
                Section("Сумма перевода") {
                    MoneyField(title: "От", amount: $minAmount)
                    MoneyField(title: "До", amount: $maxAmount)
                    Button("Сохранить диапазон", action: saveRange)
                }
                Section {
                    Stepper("Окно: \(formatDayCount(rule.windowDays))", value: Binding(
                        get: { rule.windowDays },
                        set: { days in saveWindow(days) }
                    ), in: 0...15)
                } footer: {
                    Text(rule.afterEvent == .advance ? "Считаются переводы в эти дни после аванса." : "Считаются переводы в эти дни после зарплаты.")
                }
                LabeledContent("Категория", value: categoryName)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .navigationTitle(makeAmountRuleTitle(rule))
        .onAppear {
            minAmount = rule.minAmount
            maxAmount = rule.maxAmount
        }
    }

    private func saveRange() {
        guard let minAmount, let maxAmount, minAmount <= maxAmount else {
            errorStore.show(RuleEditError.badRange)
            return
        }
        do {
            try rulesStore.updateAmountRange(rule, minAmount: minAmount, maxAmount: maxAmount)
        } catch {
            errorStore.show(error)
        }
    }

    private func saveWindow(_ days: Int) {
        do {
            try rulesStore.updateWindowDays(rule, windowDays: days)
        } catch {
            errorStore.show(error)
        }
    }
}

enum RuleEditError: LocalizedError {
    case badRange

    var errorDescription: String? {
        "Сумма «от» должна быть не больше суммы «до»."
    }
}

/// «100 000 ₸ после зарплаты», «53 500–54 500 ₸ после аванса», «Всё до 01.03.2026».
private func makeAmountRuleTitle(_ rule: AmountRule) -> String {
    if let beforeDay = rule.beforeDay {
        return "Всё до \(formatShortDay(beforeDay))"
    }
    let range = rule.minAmount == rule.maxAmount
        ? formatTenge(rule.minAmount)
        : "\(formatTenge(rule.minAmount))–\(formatTenge(rule.maxAmount))"
    switch rule.afterEvent {
    case .advance: return "\(range) после аванса"
    case .salary: return "\(range) после зарплаты"
    case nil: return range
    }
}
