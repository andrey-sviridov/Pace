import SwiftUI
import PaceCore

/// Календарь журнала: сетка месяца, в каждом дне «+доход» и «−траты»; тап по дню — его операции ниже.
/// Переводы между своими счетами не считаются — те же правила, что у главной и аналитики.
struct JournalCalendar: View {
    let today: CalendarDay
    let entries: [JournalEntry]
    let categories: [SpendingCategory]

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.theme) private var theme

    /// Любой день показанного месяца; nil — месяц сегодняшнего дня.
    @State private var shownMonthDay: CalendarDay?
    @State private var selectedDay: CalendarDay?

    var body: some View {
        let month = makeCalendarMonth(containing: shownMonthDay ?? today)
        let totals = calculateDailyTotals(month: month, entries: entries, categories: categories)
        let monthIncome = totals.values.reduce(Decimal(0)) { sum, day in sum + day.income }
        let monthSpending = totals.values.reduce(Decimal(0)) { sum, day in sum + day.spending }
        let categoryNamesById = makeCategoryNamesById(categories)
        let dayEntries = selectedDay.map { day in entries.filter { entry in entry.day == day } } ?? []

        List {
            Section {
                MonthStepper(
                    title: formatMonthTitle(month),
                    canGoNext: month.endExclusive <= today,
                    theme: theme,
                    onPrevious: { showMonth(containing: month.start.adding(days: -1)) },
                    onNext: { showMonth(containing: month.endExclusive) }
                )
                MonthGrid(
                    cells: makeMonthGridCells(month: month),
                    totals: totals,
                    selectedDay: selectedDay,
                    today: today,
                    theme: theme,
                    onSelect: { day in selectedDay = day }
                )
                HStack {
                    Text("Итого за месяц")
                        .foregroundStyle(theme.secondaryText)
                    Spacer()
                    Text("+\(formatThousands(monthIncome))").foregroundStyle(theme.income)
                    Text("·").foregroundStyle(theme.secondaryText)
                    Text("−\(formatThousands(monthSpending))").foregroundStyle(theme.text)
                }
                .font(.footnote)
                .monospacedDigit()
            }
            .listRowBackground(theme.card)

            if let selectedDay {
                Section(formatDayWithWeekday(selectedDay)) {
                    if dayEntries.isEmpty {
                        Text("В этот день операций нет")
                            .foregroundStyle(theme.secondaryText)
                    }
                    ForEach(dayEntries, id: \.id) { entry in
                        NavigationLink(value: entry) {
                            JournalRow(
                                entry: entry,
                                categoryName: makeCategoryName(categoryId: entry.categoryId, namesById: categoryNamesById),
                                isTimeShown: settingsStore.settings.shouldShowOperationTime,
                                theme: theme
                            )
                        }
                    }
                }
                .listRowBackground(theme.card)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func showMonth(containing day: CalendarDay) {
        shownMonthDay = day
        selectedDay = nil
    }
}

private struct MonthStepper: View {
    let title: String
    let canGoNext: Bool
    let theme: Theme
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Предыдущий месяц")
            Spacer()
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.text)
            Spacer()
            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
            .disabled(!canGoNext)
            .accessibilityLabel("Следующий месяц")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(theme.accent)
    }
}

private struct MonthGrid: View {
    let cells: [CalendarDay?]
    let totals: [CalendarDay: DayTotals]
    let selectedDay: CalendarDay?
    let today: CalendarDay
    let theme: Theme
    let onSelect: (CalendarDay) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"], id: \.self) { weekday in
                Text(weekday)
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryText)
            }
            ForEach(cells.indices, id: \.self) { index in
                if let day = cells[index] {
                    DayCell(
                        day: day,
                        totals: totals[day],
                        isSelected: day == selectedDay,
                        isToday: day == today,
                        theme: theme,
                        onTap: { onSelect(day) }
                    )
                } else {
                    Color.clear.frame(height: 50)
                }
            }
        }
    }
}

/// Клетка дня: число, «+доход» зелёным, «−траты». Крупный день (траты больше 40 000 ₸) — траты красным.
private struct DayCell: View {
    let day: CalendarDay
    let totals: DayTotals?
    let isSelected: Bool
    let isToday: Bool
    let theme: Theme
    let onTap: () -> Void

    var body: some View {
        let income = totals?.income ?? 0
        let spending = totals?.spending ?? 0
        let isLargeDay = spending > 40_000

        Button(action: onTap) {
            VStack(spacing: 1) {
                Text("\(day.day)")
                    .font(.footnote.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? theme.accent : theme.text)
                if income > 0 {
                    Text("+\(formatThousands(income))")
                        .foregroundStyle(theme.income)
                }
                if spending > 0 {
                    Text("−\(formatThousands(spending))")
                        .foregroundStyle(isLargeDay ? theme.over : theme.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 10))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .top)
            .padding(.vertical, 3)
            .background(isSelected ? theme.accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? theme.accent : .clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(makeDayAccessibilityText(day: day, income: income, spending: spending))
    }
}

private func makeDayAccessibilityText(day: CalendarDay, income: Decimal, spending: Decimal) -> String {
    var parts = [formatDayWithWeekday(day)]
    if income > 0 { parts.append("пришло \(formatTenge(income))") }
    if spending > 0 { parts.append("потрачено \(formatTenge(spending))") }
    return parts.joined(separator: ", ")
}
