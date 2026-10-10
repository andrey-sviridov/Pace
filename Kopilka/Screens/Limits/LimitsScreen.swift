import SwiftUI
import SwiftData
import KopilkaCore

/// «Лимиты на месяц» (спека §5.8, §8): план дохода, цель «Отложить», обязательные с ожидаемой суммой,
/// гибкие с лимитом. Списки — из @Query, поэтому главная и этот экран видят правку сразу после сохранения.
struct LimitsScreen: View {
    let today: CalendarDay

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(RulesStore.self) private var rulesStore
    @Environment(ErrorStore.self) private var errorStore
    @Environment(\.theme) private var theme

    @Query private var entries: [JournalEntry]
    @Query(sort: \SpendingCategory.sortOrder) private var categories: [SpendingCategory]

    @State private var editedAmount: LimitsEditedAmount?

    var body: some View {
        let monthlySavingsGoal = settingsStore.settings.monthlySavingsGoal
        let income = calculateTypicalMonthlyIncome(entries: entries, categories: categories, before: today, monthCount: 3)
        let obligatoryRows = makeLimitRows(categories: categories, kind: .obligatory, entries: entries, before: today, monthCount: 3)
        let flexibleRows = makeLimitRows(categories: categories, kind: .flexible, entries: entries, before: today, monthCount: 6)
        let plan = calculateLimitPlan(monthlyIncome: income, obligatoryRows: obligatoryRows, flexibleRows: flexibleRows, monthlySavingsGoal: monthlySavingsGoal)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    LimitPlanView(plan: plan, theme: theme)
                }
                Card {
                    Button {
                        editedAmount = .savingsGoal
                    } label: {
                        LimitRow(title: "Цель: отложить", subtitle: "в месяц", value: formatTenge(monthlySavingsGoal), theme: theme)
                    }
                    .buttonStyle(.plain)
                }
                LimitSection(title: "Обязательные · списываются сразу", theme: theme) {
                    ForEach(obligatoryRows, id: \.category.id) { row in
                        Button {
                            editedAmount = .expected(row)
                        } label: {
                            LimitRow(
                                title: row.category.name,
                                subtitle: makeObligatorySubtitle(row: row),
                                value: formatTenge(roundUpToWholeTenge(row.plannedMonthly ?? 0)),
                                theme: theme
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                LimitSection(title: "Гибкие · следим", theme: theme) {
                    ForEach(flexibleRows, id: \.category.id) { row in
                        NavigationLink(value: HomeDestination.categoryLimit(categoryId: row.category.id)) {
                            LimitRow(
                                title: row.category.name,
                                subtitle: "в среднем \(formatThousands(row.averageMonthly))",
                                value: row.plannedMonthly.map { limit in formatTenge(limit) } ?? "без лимита",
                                isValueMuted: row.plannedMonthly == nil,
                                theme: theme
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .background(theme.background)
        .navigationTitle("Лимиты на месяц")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editedAmount) { edited in
            makeEditorSheet(edited, monthlySavingsGoal: monthlySavingsGoal)
        }
    }

    @ViewBuilder
    private func makeEditorSheet(_ edited: LimitsEditedAmount, monthlySavingsGoal: Decimal) -> some View {
        switch edited {
        case .savingsGoal:
            // Цели ещё нет — поле пустое, чтобы не дописывать цифры к «0».
            AmountEditorSheet(title: "Цель: отложить", fieldTitle: "Сумма в месяц", initialAmount: monthlySavingsGoal > 0 ? monthlySavingsGoal : nil) { amount in
                updateSavingsGoal(amount)
            }
        case .expected(let row):
            AmountEditorSheet(
                title: row.category.name,
                fieldTitle: "Ожидаемая сумма в месяц",
                initialAmount: row.plannedMonthly,
                hint: "В среднем \(formatTenge(row.averageMonthly)) за 3 месяца",
                resetTitle: row.category.expectedMonthlyAmount == nil ? nil : "Сбросить на среднее",
                onReset: { resetExpectedAmount(of: row.category) },
                onSave: { amount in updateExpectedAmount(amount, of: row.category) }
            )
        }
    }

    private func updateSavingsGoal(_ amount: Decimal) {
        do {
            try settingsStore.updateSavingsGoal(amount)
        } catch {
            errorStore.show(error)
        }
    }

    private func updateExpectedAmount(_ amount: Decimal, of category: SpendingCategory) {
        do {
            try rulesStore.updateExpectedAmount(amount, of: category)
        } catch {
            errorStore.show(error)
        }
    }

    private func resetExpectedAmount(of category: SpendingCategory) {
        do {
            try rulesStore.resetExpectedAmount(of: category)
        } catch {
            errorStore.show(error)
        }
    }
}

/// Какая сумма сейчас правится в окне.
private enum LimitsEditedAmount: Identifiable {
    case savingsGoal
    case expected(CategoryLimitRow)

    var id: String {
        switch self {
        case .savingsGoal:
            return "savingsGoal"
        case .expected(let row):
            return row.category.id
        }
    }
}

/// «в среднем 22k» или «в среднем 22k · задано вручную».
private func makeObligatorySubtitle(row: CategoryLimitRow) -> String {
    let averageText = "в среднем \(formatThousands(row.averageMonthly))"
    guard row.category.expectedMonthlyAmount != nil else { return averageText }
    return "\(averageText) · задано вручную"
}

// MARK: - Части экрана

/// План: доход → обязательные → цель → сумма лимитов → не распределено (или «сверх дохода» статусным цветом).
private struct LimitPlanView: View {
    let plan: LimitPlan
    let theme: Theme

    var body: some View {
        let isOverAllocated = plan.unallocated < 0
        let restSegment = isOverAllocated
            ? BudgetBarSegment(title: "Сверх дохода", amount: -plan.unallocated, color: theme.over, isOverAmount: true)
            : BudgetBarSegment(title: "Не распределено", amount: plan.unallocated, color: theme.track, hasOutlinedMarker: true)
        let segments = [
            BudgetBarSegment(title: "Обязательные", amount: plan.obligatoryTotal, color: theme.secondaryText.opacity(0.55)),
            BudgetBarSegment(title: "Цель: отложить", amount: plan.savingsGoal, color: theme.accent.opacity(0.45)),
            BudgetBarSegment(title: "Сумма лимитов", amount: plan.limitsTotal, color: theme.accent),
            restSegment,
        ]

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Доход ≈ \(formatTenge(roundDownToWholeTenge(plan.income)))")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(theme.text)
                Text("обычно за месяц, по последним 3 месяцам")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
            }
            BudgetBar(segments: segments, theme: theme)
            if isOverAllocated {
                Text("Распределено на \(formatTenge(roundUpToWholeTenge(-plan.unallocated))) больше, чем приходит")
                    .font(.subheadline)
                    .foregroundStyle(theme.over)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LimitSection<Content: View>: View {
    let title: String
    let theme: Theme
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote)
                .textCase(.uppercase)
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, 4)
            Card {
                VStack(spacing: 14) {
                    content
                }
            }
        }
    }
}

/// Строка: название и «в среднем Nk» слева, сумма и «›» справа.
private struct LimitRow: View {
    let title: String
    let subtitle: String
    let value: String
    var isValueMuted = false
    let theme: Theme

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(theme.text)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(isValueMuted ? theme.secondaryText : theme.text)
            Text("›")
                .foregroundStyle(theme.secondaryText)
        }
        .contentShape(Rectangle())
    }
}
