import SwiftUI
import SwiftData
import Charts
import PaceCore

/// Куда ведут переходы с аналитики.
enum AnalyticsDestination: Hashable {
    case categoryMerchants(categoryId: String, period: Period)
}

/// Аналитика (спека §8): за выбранный период — темп трат против плана, траты по категориям, копилка по периодам.
/// Всё считает ядро; экран только раскладывает.
struct AnalyticsScreen: View {
    let today: CalendarDay

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(ErrorStore.self) private var errorStore
    @Environment(\.theme) private var theme

    @Query private var entries: [JournalEntry]
    @Query(sort: \SpendingCategory.sortOrder) private var categories: [SpendingCategory]

    /// Середина выбранного периода; nil — текущий. Хранится день, а не период: при смене режима
    /// «Сентябрь» зарплатный (28 авг – 29 сен) становится календарным сентябрём, а не августом.
    @State private var shownDay: CalendarDay?
    @State private var path: [AnalyticsDestination] = []

    var body: some View {
        let mode = settingsStore.settings.periodMode
        // Те же границы аванса и разовой премии, что у главной и импорта.
        let salaryEvents = findSalaryEvents(entries: entries, advanceDayRange: SalaryDetection.advanceDayRange, oneOffAboveMedianTimes: SalaryDetection.oneOffAboveMedianTimes)
        let period = makePeriod(containing: shownDay ?? today, mode: mode, salaryEvents: salaryEvents)
        let previousPeriod = makePreviousPeriod(before: period, mode: mode, salaryEvents: salaryEvents)
        let nextPeriod = makeNextPeriod(after: period, today: today, mode: mode, salaryEvents: salaryEvents)

        let spending = calculateCumulativeSpending(period: period, today: today, entries: entries, categories: categories)
        let plan = makeSpendingPlan(period: period, mode: mode, entries: entries, categories: categories, flexibleLookbackMonthCount: 6)
        // Восемь самых больших категорий и «Прочее».
        let categoryRows = makeTopCategoryRows(calculateSpendingByCategory(period: period, entries: entries, categories: categories), maxRowCount: 9)
        let leftoverPeriods = makeLeftoverPeriods(endingWith: period, mode: mode, salaryEvents: salaryEvents, count: 6)
        let leftovers = calculateMonthlyLeftover(months: leftoverPeriods, entries: entries, categories: categories)

        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PeriodPicker(selection: Binding(get: { mode }, set: updatePeriodMode))
                    PeriodStepper(
                        title: formatPeriodTitle(period, today: today),
                        dates: formatPeriodDates(period),
                        canGoBack: hasEntries(before: period.start, entries: entries),
                        canGoForward: nextPeriod != nil,
                        theme: theme,
                        onPrevious: { showPeriod(previousPeriod) },
                        onNext: { showPeriod(nextPeriod) }
                    )
                    Card {
                        PaceChart(period: period, today: today, spending: spending, plan: plan, theme: theme)
                    }
                    Card {
                        CategoryChart(rows: categoryRows, namesById: makeCategoryNamesById(categories), theme: theme) { categoryId in
                            path.append(.categoryMerchants(categoryId: categoryId, period: period))
                        }
                    }
                    Card {
                        LeftoverChart(leftovers: leftovers, today: today, theme: theme)
                    }
                }
                .padding()
            }
            .background(theme.background)
            .navigationTitle("Аналитика")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AnalyticsDestination.self) { destination in
                switch destination {
                case .categoryMerchants(let categoryId, let period):
                    CategoryMerchantsScreen(categoryId: categoryId, period: period)
                }
            }
        }
    }

    /// Дошли до периода, где лежит сегодня, — снова «текущий», чтобы он двигался вместе с датой.
    private func showPeriod(_ period: Period?) {
        guard let period else { return }
        shownDay = period.contains(today) ? nil : findMiddleDay(of: period)
    }

    private func updatePeriodMode(_ mode: PeriodMode) {
        do {
            try settingsStore.updatePeriodMode(mode)
        } catch {
            errorStore.show(error)
        }
    }
}

// MARK: - Листание периодов

/// «‹ Сентябрь ›»; в будущее и в периоды до первой выписки не листаем.
private struct PeriodStepper: View {
    let title: String
    let dates: String?
    let canGoBack: Bool
    let canGoForward: Bool
    let theme: Theme
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .disabled(!canGoBack)
            .accessibilityLabel("Предыдущий период")
            Spacer()
            VStack(spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(theme.text)
                if let dates {
                    Text(dates)
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .disabled(!canGoForward)
            .accessibilityLabel("Следующий период")
        }
        .tint(theme.accent)
    }
}

// MARK: - Успеваю ли я?

/// Точка графика темпа: номер дня в периоде (с 1) и суммы к концу дня.
private struct PacePoint: Identifiable {
    let id: Int
    let total: Decimal
    let obligatoryTotal: Decimal
}

/// Накопленные траты (линия и бледная заливка) против пунктира плана; обязательные — серой заливкой снизу,
/// чтобы скачок в день ипотеки был виден как обязательный, а не как «сорвался».
private struct PaceChart: View {
    let period: Period
    let today: CalendarDay
    let spending: [DailySpending]
    let plan: [DailyPlan]
    let theme: Theme

    @State private var selectedDayNumber: Int?

    var body: some View {
        let spentPoints = spending.enumerated().map { index, item in PacePoint(id: index + 1, total: item.total, obligatoryTotal: item.obligatoryTotal) }
        let planPoints = plan.enumerated().map { index, item in PacePoint(id: index + 1, total: item.total, obligatoryTotal: item.obligatoryTotal) }
        let spentTotal = spending.last?.total ?? 0
        let plannedTotal = plan.last?.total ?? 0
        let caption = makePaceCaption(spentTotal: spentTotal, plannedTotal: plannedTotal, period: period, today: today)

        VStack(alignment: .leading, spacing: 10) {
            Text("Успеваю ли я?")
                .font(.headline)
                .foregroundStyle(theme.text)
            if spentTotal == 0 && plannedTotal == 0 {
                Text("В этом периоде нет ни трат, ни плана")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
            } else {
                Text(makeShownCaption(caption: caption))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(theme.secondaryText)
                    .frame(minHeight: 34, alignment: .topLeading)
                Chart {
                    ForEach(spentPoints) { point in
                        AreaMark(
                            x: .value("День", point.id),
                            yStart: .value("От", 0),
                            yEnd: .value("Обязательные, тыс.", makeThousands(point.obligatoryTotal)),
                            series: .value("Ряд", "Обязательные")
                        )
                        .foregroundStyle(theme.secondaryText.opacity(0.25))
                    }
                    ForEach(spentPoints) { point in
                        AreaMark(
                            x: .value("День", point.id),
                            yStart: .value("Обязательные, тыс.", makeThousands(point.obligatoryTotal)),
                            yEnd: .value("Потрачено, тыс.", makeThousands(point.total)),
                            series: .value("Ряд", "Гибкие")
                        )
                        .foregroundStyle(theme.accent.opacity(0.1))
                    }
                    ForEach(planPoints) { point in
                        LineMark(x: .value("День", point.id), y: .value("План, тыс.", makeThousands(point.total)), series: .value("Ряд", "План"))
                            .foregroundStyle(theme.secondaryText)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
                    ForEach(spentPoints) { point in
                        LineMark(x: .value("День", point.id), y: .value("Потрачено, тыс.", makeThousands(point.total)), series: .value("Ряд", "Потрачено"))
                            .foregroundStyle(theme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    if let lastPoint = spentPoints.last {
                        PointMark(x: .value("День", lastPoint.id), y: .value("Потрачено, тыс.", makeThousands(lastPoint.total)))
                            .foregroundStyle(theme.accent)
                            .symbolSize(50)
                    }
                    if let selectedDayNumber {
                        RuleMark(x: .value("День", selectedDayNumber))
                            .foregroundStyle(theme.secondaryText)
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                }
                .chartXScale(domain: 1...max(period.dayCount, 2))
                .chartXSelection(value: $selectedDayNumber)
                .chartXAxis {
                    AxisMarks(values: makeAxisDayNumbers(dayCount: period.dayCount)) { value in
                        let dayNumber = value.as(Int.self) ?? 1
                        // Крайние подписи прижаты внутрь: по центру последнюю Swift Charts обрезает и прячет.
                        AxisValueLabel(anchor: makeAxisLabelAnchor(dayNumber: dayNumber, dayCount: period.dayCount)) {
                            Text(formatShortDay(period.start.adding(days: dayNumber - 1)))
                        }
                        .foregroundStyle(theme.secondaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                            .foregroundStyle(theme.track)
                        AxisValueLabel {
                            if let thousands = value.as(Double.self) {
                                Text(formatAxisThousands(thousands))
                            }
                        }
                        .foregroundStyle(theme.secondaryText)
                    }
                }
                .frame(height: 200)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Темп трат")
                .accessibilityValue(makePaceAccessibilityText(caption: caption, spending: spending, plan: plan))
                PaceLegend(theme: theme)
            }
        }
    }

    /// Пока палец на графике — день и суммы под ним, иначе общий итог.
    private func makeShownCaption(caption: String) -> String {
        guard let selectedDayNumber else { return caption }
        let index = min(max(selectedDayNumber, 1), plan.count) - 1
        guard plan.indices.contains(index) else { return caption }
        let selectedSpending = spending.indices.contains(index) ? spending[index] : nil
        return makePaceSelectionText(plan: plan[index], spending: selectedSpending)
    }
}

/// Три ряда — легенда обязательна: цвет не единственный способ понять, где что.
private struct PaceLegend: View {
    let theme: Theme

    var body: some View {
        HStack(spacing: 14) {
            LegendKey(title: "Потрачено", theme: theme) {
                Capsule().fill(theme.accent).frame(width: 14, height: 2)
            }
            LegendKey(title: "План", theme: theme) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 1))
                    path.addLine(to: CGPoint(x: 14, y: 1))
                }
                .stroke(theme.secondaryText, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: 14, height: 2)
            }
            LegendKey(title: "Обязательные", theme: theme) {
                RoundedRectangle(cornerRadius: 2).fill(theme.secondaryText.opacity(0.25)).frame(width: 10, height: 10)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct LegendKey<Key: View>: View {
    let title: String
    let theme: Theme
    @ViewBuilder let key: Key

    var body: some View {
        HStack(spacing: 5) {
            key
            Text(title)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
    }
}

/// Начало, середина и конец периода: подписи каждого дня на узком экране слиплись бы.
private func makeAxisDayNumbers(dayCount: Int) -> [Int] {
    guard dayCount > 2 else { return [1, max(dayCount, 1)] }
    return [1, (dayCount + 1) / 2, dayCount]
}

private func makeAxisLabelAnchor(dayNumber: Int, dayCount: Int) -> UnitPoint {
    guard dayNumber > 1 else { return .topLeading }
    guard dayNumber < dayCount else { return .topTrailing }
    return .top
}

private func makePaceAccessibilityText(caption: String, spending: [DailySpending], plan: [DailyPlan]) -> String {
    let obligatorySpent = spending.last?.obligatoryTotal ?? 0
    let obligatoryPlanned = plan.last?.obligatoryTotal ?? 0
    return "\(caption). Из них обязательные: потрачено \(formatTenge(obligatorySpent)), по плану \(formatTenge(obligatoryPlanned))."
}

// MARK: - Куда уходят деньги?

/// Строка диаграммы категорий с готовым названием.
private struct CategoryBar: Identifiable {
    let id: String
    let categoryId: String?
    let name: String
    let total: Decimal
}

/// Одна величина — один цвет: полосы различаются длиной, а не оттенком.
/// Каждая строка — кнопка со стрелкой «›» и подсветкой при нажатии: видно, что её можно открыть.
private struct CategoryChart: View {
    let rows: [CategorySpendingRow]
    let namesById: [String: String]
    let theme: Theme
    let onOpenCategory: (String) -> Void

    var body: some View {
        let bars = makeCategoryBars(rows: rows, namesById: namesById)
        let maxTotal = bars.map { bar in bar.total }.max() ?? 0

        VStack(alignment: .leading, spacing: 6) {
            Text("Куда уходят деньги?")
                .font(.headline)
                .foregroundStyle(theme.text)
            if bars.isEmpty {
                Text("В этом периоде трат нет")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
            } else {
                ForEach(bars) { bar in
                    CategoryBarRow(bar: bar, maxTotal: maxTotal, theme: theme) {
                        openCategory(bar)
                    }
                }
            }
        }
    }

    /// «Прочее» — несколько категорий сразу, продавцов у него нет.
    private func openCategory(_ bar: CategoryBar) {
        guard let categoryId = bar.categoryId else { return }
        onOpenCategory(categoryId)
    }
}

private struct CategoryBarRow: View {
    let bar: CategoryBar
    let maxTotal: Decimal
    let theme: Theme
    let onTap: () -> Void

    var body: some View {
        let isOpenable = bar.categoryId != nil
        let share = maxTotal > 0 ? makeDouble(bar.total / maxTotal) : 0

        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(bar.name)
                        .font(.subheadline)
                        .foregroundStyle(theme.text)
                    Spacer()
                    Text(formatThousands(bar.total))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(theme.secondaryText)
                    if isOpenable {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                GeometryReader { geometry in
                    Capsule()
                        .fill(theme.accent)
                        .frame(width: max(geometry.size.width * share, 4), height: 8)
                }
                .frame(height: 8)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressedRowStyle(highlight: theme.track))
        .disabled(!isOpenable)
        .accessibilityLabel("\(bar.name), \(formatTenge(bar.total))")
        .accessibilityHint(isOpenable ? "Показать продавцов" : "")
    }
}

/// Подсветка строки, пока палец на ней, — как у строк списка в iOS.
private struct PressedRowStyle: ButtonStyle {
    let highlight: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? highlight : .clear, in: RoundedRectangle(cornerRadius: 10))
    }
}

private func makeCategoryBars(rows: [CategorySpendingRow], namesById: [String: String]) -> [CategoryBar] {
    rows.map { row in
        guard let categoryId = row.categoryId else {
            return CategoryBar(id: "other", categoryId: nil, name: "Прочее", total: row.total)
        }
        // Траты без категории ядро собирает под id "uncategorized" — называем их, как журнал.
        let name = makeCategoryName(categoryId: categoryId == "uncategorized" ? nil : categoryId, namesById: namesById)
        return CategoryBar(id: categoryId, categoryId: categoryId, name: name, total: row.total)
    }
}

// MARK: - Получается ли копить?

/// Столбик «осталось» одного периода.
private struct LeftoverBar: Identifiable {
    let id: Int
    let label: String
    let leftover: Decimal
    let isFinished: Bool
}

/// Плюс — цветом акцента, минус — цветом перерасхода и со знаком «−» в подписи, не только цветом.
/// Идущий период бледнее: он ещё без зарплаты, и в среднее не входит.
private struct LeftoverChart: View {
    let leftovers: [PeriodLeftover]
    let today: CalendarDay
    let theme: Theme

    var body: some View {
        let bars = leftovers.enumerated().map { index, item in
            LeftoverBar(id: index, label: formatPeriodLabel(item.period), leftover: item.leftover, isFinished: item.period.endExclusive <= today)
        }
        let thousands = bars.map { bar in makeThousands(bar.leftover) }
        let lowest = min(thousands.min() ?? 0, 0)
        let highest = max(thousands.max() ?? 0, 0)
        // Запас под подписи у концов столбиков — от всего размаха: подпись короткого минуса иначе налезает на месяцы.
        let labelRoom = max((highest - lowest) * 0.15, 1)
        let averageLeftover = calculateAverageLeftover(leftovers, today: today)

        VStack(alignment: .leading, spacing: 10) {
            Text("Получается ли копить?")
                .font(.headline)
                .foregroundStyle(theme.text)
            if bars.allSatisfy({ bar in bar.leftover == 0 }) {
                Text("За последние периоды нет ни дохода, ни трат")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
            } else {
                Text(averageLeftover.map { average in makeLeftoverCaption(averageLeftover: average) } ?? "Закончившихся периодов пока нет")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(theme.secondaryText)
                Chart {
                    ForEach(bars) { bar in
                        BarMark(x: .value("Период", bar.label), y: .value("Осталось, тыс.", makeThousands(bar.leftover)), width: .fixed(22))
                            .foregroundStyle(bar.leftover < 0 ? theme.over : theme.accent)
                            .opacity(bar.isFinished ? 1 : 0.45)
                            .cornerRadius(4)
                            .annotation(position: bar.leftover < 0 ? .bottom : .top, spacing: 4) {
                                Text(formatSignedThousands(bar.leftover))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(theme.secondaryText)
                            }
                    }
                    RuleMark(y: .value("Ноль", 0))
                        .foregroundStyle(theme.secondaryText)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
                .chartYScale(domain: (lowest < 0 ? lowest - labelRoom : 0)...(highest > 0 ? highest + labelRoom : 1))
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                            .foregroundStyle(theme.track)
                        AxisValueLabel {
                            if let thousands = value.as(Double.self) {
                                Text(formatAxisThousands(thousands))
                            }
                        }
                        .foregroundStyle(theme.secondaryText)
                    }
                }
                .frame(height: 200)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Осталось по периодам")
                .accessibilityValue(makeLeftoverAccessibilityText(bars: bars))
                if bars.last?.isFinished == false {
                    Text("Бледный столбик — период ещё идёт, в среднее он не входит")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                }
            }
        }
    }
}

private func makeLeftoverAccessibilityText(bars: [LeftoverBar]) -> String {
    let barTexts = bars.map { bar in
        let amountText = bar.leftover < 0 ? "минус \(formatTenge(-bar.leftover))" : formatTenge(bar.leftover)
        return bar.isFinished ? "\(bar.label) \(amountText)" : "\(bar.label) \(amountText), период ещё идёт"
    }
    return barTexts.joined(separator: ", ")
}
