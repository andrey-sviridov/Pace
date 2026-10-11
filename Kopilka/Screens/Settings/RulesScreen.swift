import SwiftUI
import SwiftData
import KopilkaCore

/// «Правила категорий»: переводы по сумме (кому ушёл перевод — в выписке не видно) и продавец → категория.
/// Любое правило можно поправить или удалить смахиванием. Уже размеченные записи правка не меняет.
struct RulesScreen: View {
    @Environment(\.theme) private var theme

    @Query(sort: \MerchantRule.merchantKey) private var merchantRules: [MerchantRule]
    @Query(sort: \AmountRule.sortOrder) private var amountRules: [AmountRule]
    @Query private var categories: [SpendingCategory]

    @State private var query = ""
    @State private var isAddingAmountRule = false

    var body: some View {
        let namesById = makeCategoryNamesById(categories)
        let foundRules = merchantRules.filter { rule in
            query.isEmpty || rule.merchantKey.localizedCaseInsensitiveContains(query)
        }

        List {
            AmountRulesSection(
                rules: amountRules,
                categories: categories,
                namesById: namesById,
                onAdd: { isAddingAmountRule = true }
            )
            MerchantRulesSection(title: "Мои правила", rules: foundRules.filter { rule in !rule.isBuiltIn }, categories: categories, namesById: namesById)
            MerchantRulesSection(title: "Встроенные", rules: foundRules.filter { rule in rule.isBuiltIn }, categories: categories, namesById: namesById)
        }
        .searchable(text: $query, prompt: "MAGNUM")
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .navigationTitle("Правила")
        .sheet(isPresented: $isAddingAmountRule) {
            NavigationStack { AmountRuleEditor(rule: nil, categories: categories) }
        }
    }
}

// MARK: - Переводы по сумме

private struct AmountRulesSection: View {
    let rules: [AmountRule]
    let categories: [SpendingCategory]
    let namesById: [String: String]
    let onAdd: () -> Void

    @Environment(RulesStore.self) private var rulesStore
    @Environment(ErrorStore.self) private var errorStore

    var body: some View {
        Section {
            ForEach(rules) { rule in
                NavigationLink {
                    AmountRuleEditor(rule: rule, categories: categories)
                } label: {
                    AmountRuleRow(rule: rule, targetName: makeTargetName(rule, namesById: namesById))
                }
                .swipeActions {
                    // Иконка вместо слова: красная, как привычное удаление в iOS.
                    Button { delete(rule) } label: {
                        Image(systemName: "trash")
                    }
                    .tint(.red)
                    .accessibilityLabel("Удалить правило")
                }
            }
            Button("Добавить правило", action: onAdd)
                .font(.subheadline)
        } header: {
            Text("Переводы по сумме")
        } footer: {
            Text("В выписке не видно, кому ушёл перевод. Правило узнаёт его по сумме и дню после зарплаты или аванса.")
        }
    }

    private func delete(_ rule: AmountRule) {
        do {
            try rulesStore.deleteAmountRule(rule)
        } catch {
            errorStore.show(error)
        }
    }
}

private struct AmountRuleRow: View {
    let rule: AmountRule
    let targetName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(makeAmountRuleTitle(rule))
                .font(.subheadline)
            Text("→ \(targetName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Добавление (rule == nil) и правка правила сумм.
private struct AmountRuleEditor: View {
    let rule: AmountRule?
    let categories: [SpendingCategory]

    @Environment(RulesStore.self) private var rulesStore
    @Environment(ErrorStore.self) private var errorStore
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var minAmount: Decimal?
    @State private var maxAmount: Decimal?
    @State private var afterEvent: SalaryEventKind?
    @State private var windowDays = 3
    @State private var categoryId: String?
    @State private var isPickingCategory = false

    var body: some View {
        let namesById = makeCategoryNamesById(categories)

        Form {
            Section {
                MoneyField(title: "От", amount: $minAmount)
                MoneyField(title: "До", amount: $maxAmount)
            } header: {
                Text("Сумма перевода")
            } footer: {
                Text("Для точной суммы впишите одно и то же число в оба поля.")
            }
            Section {
                Picker("Когда", selection: $afterEvent) {
                    Text("После зарплаты").tag(SalaryEventKind?.some(.salary))
                    Text("После аванса").tag(SalaryEventKind?.some(.advance))
                    Text("В любой день").tag(SalaryEventKind?.none)
                }
                if afterEvent != nil {
                    Stepper("Окно: \(formatDayCount(windowDays))", value: $windowDays, in: 0...15)
                }
            }
            Section {
                Button { isPickingCategory = true } label: {
                    LabeledContent("Категория", value: categoryId.map { id in makeCategoryName(categoryId: id, namesById: namesById) } ?? "Выбрать")
                }
                .foregroundStyle(theme.text)
            } footer: {
                Text("«Свои переводы» — перевод на вашу другую карту: он не считается тратой.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .navigationTitle(rule == nil ? "Новое правило" : "Правило")
        .toolbar {
            if rule == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить", action: save)
            }
        }
        .sheet(isPresented: $isPickingCategory) {
            CategoryPicker(categories: categories, selectedId: categoryId) { id in categoryId = id }
        }
        .onAppear(perform: fillFromRule)
    }

    private func fillFromRule() {
        guard let rule else { return }
        minAmount = rule.minAmount
        maxAmount = rule.maxAmount
        afterEvent = rule.afterEvent
        windowDays = rule.windowDays
        categoryId = rule.targetAccountKind == .ownOtherCard ? "ownTransfer" : rule.categoryId
    }

    private func save() {
        guard let minAmount, let maxAmount, minAmount > 0, minAmount <= maxAmount else {
            errorStore.show(RuleEditError.badRange)
            return
        }
        guard let categoryId else {
            errorStore.show(RuleEditError.noCategory)
            return
        }
        let draft = AmountRuleDraft(
            minAmount: minAmount,
            maxAmount: maxAmount,
            afterEvent: afterEvent,
            windowDays: afterEvent == nil ? 0 : windowDays,
            categoryId: categoryId
        )
        do {
            if let rule {
                try rulesStore.updateAmountRule(rule, with: draft)
            } else {
                try rulesStore.addAmountRule(draft)
            }
            dismiss()
        } catch {
            errorStore.show(error)
        }
    }
}

// MARK: - Продавец → категория

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
            Section {
                ForEach(rules) { rule in
                    Button { editedRule = rule } label: {
                        LabeledContent(rule.title ?? rule.merchantKey, value: makeCategoryName(categoryId: rule.categoryId, namesById: namesById))
                    }
                    // Список длинный (сотни продавцов): мелкий шрифт помещает больше строк на экран.
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .swipeActions {
                        // Иконка вместо слова: красная, как привычное удаление в iOS.
                        Button { delete(rule) } label: {
                            Image(systemName: "trash")
                        }
                        .tint(.red)
                        .accessibilityLabel("Удалить правило")
                    }
                }
            } header: {
                Text(title)
            } footer: {
                if rules.first?.isBuiltIn == true {
                    Text("Встроенные правила приложение добавило по вашей выписке при настройке. Удалённое встроенное правило вернётся только после «Начать заново».")
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

enum RuleEditError: LocalizedError {
    case badRange
    case noCategory

    var errorDescription: String? {
        switch self {
        case .badRange: "Впишите обе суммы больше нуля, «от» — не больше «до»."
        case .noCategory: "Выберите категорию для таких переводов."
        }
    }
}

private func makeTargetName(_ rule: AmountRule, namesById: [String: String]) -> String {
    guard rule.targetAccountKind != .ownOtherCard else { return "своя карта" }
    return makeCategoryName(categoryId: rule.categoryId, namesById: namesById)
}

/// «100 000 ₸ после зарплаты», «53 500–54 500 ₸ после аванса», «20 000 ₸ в любой день».
private func makeAmountRuleTitle(_ rule: AmountRule) -> String {
    let range = rule.minAmount == rule.maxAmount
        ? formatTenge(rule.minAmount)
        : "\(formatTenge(rule.minAmount))–\(formatTenge(rule.maxAmount))"
    switch rule.afterEvent {
    case .advance: return "\(range) после аванса"
    case .salary: return "\(range) после зарплаты"
    case nil: return "\(range) в любой день"
    }
}
