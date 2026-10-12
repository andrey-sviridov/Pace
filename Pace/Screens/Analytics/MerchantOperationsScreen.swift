import SwiftUI
import SwiftData
import PaceCore

/// Операции одного продавца категории за период — открывается тапом по строке продавца.
/// Видно, когда и сколько ушло; тап по операции — её карточка с исходными данными банка.
struct MerchantOperationsScreen: View {
    let title: String
    let categoryId: String
    let period: Period

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.theme) private var theme

    /// Только записи с этим названием: все записи база отдаёт ~50 мс, и переход на экран заметно дёргался.
    @Query private var entries: [JournalEntry]
    @Query(sort: \SpendingCategory.sortOrder) private var categories: [SpendingCategory]

    init(title: String, categoryId: String, period: Period) {
        self.title = title
        self.categoryId = categoryId
        self.period = period
        _entries = Query(filter: #Predicate<JournalEntry> { entry in entry.title == title })
    }

    var body: some View {
        let operations = findMerchantOperations(title: title, categoryId: categoryId, period: period, entries: entries, categories: categories)
        let total = operations.reduce(Decimal(0)) { sum, operation in sum + operation.amount }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(formatShortDay(period.start)) – \(formatShortDay(period.endExclusive.adding(days: -1))) · \(formatOperationCount(operations.count))")
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText)
                    MoneyText(amount: total, style: .hero)
                }
                .padding(.horizontal, 4)
                Card {
                    if operations.isEmpty {
                        Text("В этом периоде операций нет")
                            .foregroundStyle(theme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(operations, id: \.entry.id) { operation in
                                NavigationLink(value: AnalyticsDestination.entry(operation.entry)) {
                                    OperationRow(operation: operation, isTimeShown: settingsStore.settings.shouldShowOperationTime, theme: theme)
                                }
                                .buttonStyle(PressedRowStyle(highlight: theme.track))
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct OperationRow: View {
    let operation: CategoryOperation
    let isTimeShown: Bool
    let theme: Theme

    var body: some View {
        let entry = operation.entry

        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatDayWithWeekday(entry.day))
                    .foregroundStyle(theme.text)
                // Заметка — обычно и есть «кому»; без неё строка — только дата и время.
                if let details = makeOperationDetails(entry: entry, isTimeShown: isTimeShown) {
                    Text(details)
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(2)
                }
            }
            Spacer()
            MoneyText(amount: operation.amount)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Открыть операцию")
    }
}

/// «14:32 · Маме на продукты»; nil — ни времени, ни заметки.
private func makeOperationDetails(entry: JournalEntry, isTimeShown: Bool) -> String? {
    var parts: [String] = []
    if isTimeShown, let time = entry.time {
        parts.append(formatOperationTime(time, calendar: .current))
    }
    let note = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
    if !note.isEmpty {
        parts.append(note)
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}
