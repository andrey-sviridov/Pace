import SwiftUI
import SwiftData
import Charts
import KopilkaCore

/// Карточка категории (спека §8): траты за 6 прошедших периодов с линией лимита, лимит крупно, ползунок,
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

    /// Положение ползунка в тенге; пока его тянут, крупная цифра и линия на графике следуют за ним.
    @State private var sliderTenge: Double = 0
    @State private var isDraggingSlider = false

    var body: some View {
        // Те же границы аванса и разовой премии, что у главной и импорта.
        let salaryEvents = findSalaryEvents(entries: entries, advanceDayRange: 10...20, oneOffAboveMedianTimes: 1.5)
        let periods = makeLimitHistoryPeriods(today: today, mode: settingsStore.settings.periodMode, salaryEvents: salaryEvents, count: 6)
        let history = calculateCategoryHistory(categoryId: category.id, periods: periods, entries: entries, categories: categories)
        let average = calculateTypicalMonthlyAmount(categoryId: category.id, entries: entries, before: today, monthCount: 6)
        let merchantTitles = makeSpan(of: periods).map { span in
            findTopMerchantTitles(categoryId: category.id, entries: entries, period: span, count: 4)
        } ?? []
        let shownLimit = isDraggingSlider ? Decimal(Int(sliderTenge.rounded())) : category.monthlyLimit
        let sliderMaximum = calculateLimitSliderMaximum(averageMonthly: average, currentLimit: category.monthlyLimit, minimumTenge: 10_000, stepTenge: 1_000)

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
                        LimitAmountHeader(limit: shownLimit, theme: theme)
                        Slider(
                            value: $sliderTenge,
                            in: 0...makeDouble(sliderMaximum),
                            step: 1_000,
                            onEditingChanged: { isEditing in finishSliderDrag(isEditing: isEditing) }
                        )
                        .tint(theme.accent)
                        .accessibilityLabel("Лимит на месяц")
                        .accessibilityValue(shownLimit.map { limit in formatTenge(limit) } ?? "без лимита")
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
                        Button("Убрать лимит", role: .destructive, action: removeMonthlyLimit)
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
        .onAppear {
            moveSlider(to: category.monthlyLimit ?? makeSuggestedLimit(averageMonthly: average, cutPercent: 0, roundingStepTenge: 1_000))
        }
    }

    /// Сохраняем, когда палец отпущен: запись на каждый шаг ползунка дёргала бы базу и главную.
    private func finishSliderDrag(isEditing: Bool) {
        isDraggingSlider = isEditing
        guard !isEditing else { return }
        updateMonthlyLimit(Decimal(Int(sliderTenge.rounded())))
    }

    private func moveSlider(to limit: Decimal) {
        sliderTenge = makeDouble(limit)
    }

    private func updateMonthlyLimit(_ limit: Decimal) {
        do {
            try rulesStore.updateMonthlyLimit(limit, of: category)
            moveSlider(to: limit)
        } catch {
            errorStore.show(error)
            moveSlider(to: category.monthlyLimit ?? 0)
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

private struct LimitAmountHeader: View {
    let limit: Decimal?
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Лимит на месяц")
                .font(.subheadline)
                .foregroundStyle(theme.secondaryText)
            Text(limit.map { amount in formatTenge(amount) } ?? "Без лимита")
                .font(theme.heroFont)
                .monospacedDigit()
                .foregroundStyle(limit == nil ? theme.secondaryText : theme.text)
        }
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

/// Ползунок и график работают с Double; это только положение на экране, сами суммы остаются в Decimal.
private func makeDouble(_ amount: Decimal) -> Double {
    NSDecimalNumber(decimal: amount).doubleValue
}

private func makeThousands(_ amount: Decimal) -> Double {
    makeDouble(amount / 1000)
}
