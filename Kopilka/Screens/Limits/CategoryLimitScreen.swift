import SwiftUI
import SwiftData
import Charts
import KopilkaCore

/// Карточка категории (спека §8): траты за 6 прошедших периодов с линией лимита, лимит крупно (нажатие — ввод суммы),
/// подсказки «Как обычно / −20% / −40%», экономия и порог предупреждения. Каждое действие сразу сохраняется.
struct CategoryLimitScreen: View {
    let category: SpendingCategory
    let today: CalendarDay

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(RulesStore.self) private var rulesStore
    @Environment(ErrorStore.self) private var errorStore
    @Environment(\.theme) private var theme

    @Query private var entries: [JournalEntry]
    @Query(sort: \SpendingCategory.sortOrder) private var categories: [SpendingCategory]

    @State private var isEditingAmount = false
    @State private var isConfirmingRemoval = false

    var body: some View {
        // Те же границы аванса и разовой премии, что у главной и импорта.
        let salaryEvents = findSalaryEvents(entries: entries, advanceDayRange: SalaryDetection.advanceDayRange, oneOffAboveMedianTimes: SalaryDetection.oneOffAboveMedianTimes)
        let periods = makeLimitHistoryPeriods(today: today, mode: settingsStore.settings.periodMode, salaryEvents: salaryEvents, count: 6)
        let history = calculateCategoryHistory(categoryId: category.id, periods: periods, entries: entries, categories: categories)
        // Среднее — по тем же столбикам, что на графике: цифры на карточке совпадают с тем, что видно.
        let average = calculateMedianAmount(history)
        let merchantTitles = makeSpan(of: periods).map { span in
            findTopMerchantTitles(categoryId: category.id, entries: entries, period: span, count: 4)
        } ?? []
        let shownLimit = category.monthlyLimit

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !merchantTitles.isEmpty {
                    Text(merchantTitles.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText)
                        .padding(.horizontal, 4)
                }
                Card {
                    CategoryHistoryChart(
                        bars: makeHistoryBars(periods: periods, amounts: history),
                        limit: shownLimit,
                        average: average,
                        theme: theme
                    )
                }
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Button { isEditingAmount = true } label: {
                            LimitAmountHeader(limit: shownLimit, theme: theme)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Ввести сумму лимита")
                        LimitPresetButtons(average: average, theme: theme) { limit in
                            updateMonthlyLimit(limit)
                        }
                        if let shownLimit, let savings = calculateLimitSavings(averageMonthly: average, monthlyLimit: shownLimit) {
                            Text("Экономия ≈ \(formatTenge(savings.perMonth)) в месяц · \(formatTenge(savings.perYear)) в год")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(theme.normal)
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Предупредить при")
                                .foregroundStyle(theme.text)
                            Spacer()
                            Picker("Предупредить при", selection: Binding(get: { category.warnAtPercent }, set: updateWarnPercent)) {
                                ForEach([70, 80, 85, 90, 100], id: \.self) { percent in
                                    Text("\(percent)%").tag(percent)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(theme.accent)
                        }
                        Button("Убрать лимит", role: .destructive) {
                            isConfirmingRemoval = true
                        }
                        .disabled(category.monthlyLimit == nil)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .background(theme.background)
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        // Плавающая панель вкладок закрывала «Убрать лимит» внизу карточки.
        .toolbar(.hidden, for: .tabBar)
        .confirmationDialog(
            makeRemovalQuestion(limit: category.monthlyLimit),
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Убрать", role: .destructive, action: removeMonthlyLimit)
            Button("Отмена", role: .cancel) {}
        }
        .sheet(isPresented: $isEditingAmount) {
            AmountEditorSheet(
                title: category.name,
                fieldTitle: "Лимит на месяц, ₸",
                initialAmount: category.monthlyLimit ?? makeSuggestedLimit(averageMonthly: average, cutPercent: 0, roundingStepTenge: 1_000),
                hint: average > 0 ? "В среднем \(formatTenge(average)) в месяц" : nil,
                onSave: updateMonthlyLimit
            )
        }
    }

    /// Нулевой лимит сразу был бы «превышен»; убирают лимит отдельной кнопкой.
    private func updateMonthlyLimit(_ limit: Decimal) {
        guard limit > 0 else {
            errorStore.show(LimitEditError.notPositive)
            return
        }
        do {
            try rulesStore.updateMonthlyLimit(limit, of: category)
        } catch {
            errorStore.show(error)
        }
    }

    private func removeMonthlyLimit() {
        do {
            try rulesStore.removeMonthlyLimit(of: category)
        } catch {
            errorStore.show(error)
        }
    }

    private func updateWarnPercent(_ percent: Int) {
        do {
            try rulesStore.updateWarnPercent(percent, of: category)
        } catch {
            errorStore.show(error)
        }
    }
}

// MARK: - График

/// Столбик периода: подпись и траты.
private struct HistoryBar: Identifiable {
    let id: Int
    let label: String
    let amount: Decimal
}

private func makeHistoryBars(periods: [Period], amounts: [Decimal]) -> [HistoryBar] {
    zip(periods, amounts).enumerated().map { index, pair in
        let (period, amount) = pair
        return HistoryBar(id: index, label: formatPeriodLabel(period), amount: amount)
    }
}

/// Один ряд одним цветом; столбики выше лимита — цветом «внимание», и подпись называет их число, чтобы не только цветом.
private struct CategoryHistoryChart: View {
    let bars: [HistoryBar]
    let limit: Decimal?
    let average: Decimal
    let theme: Theme

    var body: some View {
        let aboveLimitCount = bars.filter { bar in isAboveLimit(bar.amount) }.count
        VStack(alignment: .leading, spacing: 10) {
            Text("Последние 6 периодов, тыс.")
                .font(.subheadline)
                .foregroundStyle(theme.secondaryText)
            Chart {
                ForEach(bars) { bar in
                    BarMark(x: .value("Период", bar.label), y: .value("Траты, тыс.", makeThousands(bar.amount)), width: .ratio(0.55))
                        .foregroundStyle(isAboveLimit(bar.amount) ? theme.warning : theme.accent)
                        .cornerRadius(4)
                }
                if let limit {
                    RuleMark(y: .value("Лимит, тыс.", makeThousands(limit)))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .foregroundStyle(theme.text.opacity(0.75))
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                        .foregroundStyle(theme.track)
                    AxisValueLabel()
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .frame(height: 180)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(makeChartAccessibilityText(bars: bars, limit: limit))
            Text(makeChartCaption(limit: limit, average: average, aboveLimitCount: aboveLimitCount))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(theme.secondaryText)
        }
    }

    private func isAboveLimit(_ amount: Decimal) -> Bool {
        guard let limit else { return false }
        return amount > limit
    }
}

/// «Убрать лимит 79 000 ₸?»
private func makeRemovalQuestion(limit: Decimal?) -> String {
    guard let limit else { return "Убрать лимит?" }
    return "Убрать лимит \(formatTenge(limit))?"
}

/// «- - - новый лимит 45k · в среднем 56k · выше лимита: 3».
private func makeChartCaption(limit: Decimal?, average: Decimal, aboveLimitCount: Int) -> String {
    let averageText = "в среднем \(formatThousands(average))"
    guard let limit else { return averageText }
    let parts = ["- - - новый лимит \(formatThousands(limit))", averageText]
    guard aboveLimitCount > 0 else { return parts.joined(separator: " · ") }
    return (parts + ["выше лимита: \(aboveLimitCount)"]).joined(separator: " · ")
}

private func makeChartAccessibilityText(bars: [HistoryBar], limit: Decimal?) -> String {
    let barTexts = bars.map { bar in "\(bar.label) \(formatTenge(bar.amount))" }
    let spendingText = "Траты по периодам: " + barTexts.joined(separator: ", ")
    guard let limit else { return spendingText + ". Лимита нет." }
    return spendingText + ". Лимит \(formatTenge(limit))."
}

// MARK: - Лимит

/// Лимит крупно с карандашом: по нажатию открывается ввод суммы.
private struct LimitAmountHeader: View {
    let limit: Decimal?
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Лимит на месяц")
                .font(.subheadline)
                .foregroundStyle(theme.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(limit.map { amount in formatTenge(amount) } ?? "Задать сумму")
                    .font(theme.heroFont)
                    .monospacedDigit()
                    .foregroundStyle(limit == nil ? theme.accent : theme.text)
                Image(systemName: "pencil")
                    .font(.title3)
                    .foregroundStyle(theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

enum LimitEditError: LocalizedError {
    case notPositive

    var errorDescription: String? {
        "Лимит должен быть больше нуля. Чтобы убрать лимит, нажмите «Убрать лимит»."
    }
}

/// «Как обычно 56k» / «−20% 45k» / «−40% 34k»; без истории трат подсказывать нечего.
private struct LimitPresetButtons: View {
    let average: Decimal
    let theme: Theme
    let onSelect: (Decimal) -> Void

    var body: some View {
        let usualLimit = makeSuggestedLimit(averageMonthly: average, cutPercent: 0, roundingStepTenge: 1_000)
        let smallerLimit = makeSuggestedLimit(averageMonthly: average, cutPercent: 20, roundingStepTenge: 1_000)
        let smallestLimit = makeSuggestedLimit(averageMonthly: average, cutPercent: 40, roundingStepTenge: 1_000)
        HStack(spacing: 8) {
            LimitPresetButton(title: "Как обычно", limit: usualLimit, onSelect: onSelect)
            LimitPresetButton(title: "−20%", limit: smallerLimit, onSelect: onSelect)
            LimitPresetButton(title: "−40%", limit: smallestLimit, onSelect: onSelect)
        }
        .disabled(average <= 0)
    }
}

private struct LimitPresetButton: View {
    let title: String
    let limit: Decimal
    let onSelect: (Decimal) -> Void

    var body: some View {
        Button {
            onSelect(limit)
        } label: {
            // Название и сумма в две строки: «Как обычно · 98k» в одну строку на узком экране не влезает.
            VStack(spacing: 2) {
                Text(title)
                Text(formatThousands(limit))
                    .monospacedDigit()
                    .fontWeight(.semibold)
            }
            .font(.footnote)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - Помощники

/// Отрезок от начала первого периода до конца последнего — для продавцов в подписи.
private func makeSpan(of periods: [Period]) -> Period? {
    guard let first = periods.first, let last = periods.last else { return nil }
    return Period(start: first.start, endExclusive: last.endExclusive)
}
