import SwiftUI
import SwiftData
import PaceCore

/// Журнал (спека §8): все записи по дням, поиск по названию, фильтр по категории, счёту и источнику.
/// Склеенные записи (`mergedInto`) не показываем — они только хранят ключи источников.
struct JournalScreen: View {
    let today: CalendarDay

    @Environment(\.theme) private var theme

    @Query private var entries: [JournalEntry]
    @Query(sort: \SpendingCategory.sortOrder) private var categories: [SpendingCategory]
    @Query(sort: \Account.title) private var accounts: [Account]

    @State private var query = ""
    @State private var filter = JournalFilter()
    @State private var isCalendarShown = false

    var body: some View {
        let visibleEntries = entries.filter { entry in entry.mergedInto == nil }
        let foundEntries = findEntries(visibleEntries, query: query, filter: filter)
        let groups = makeDayGroups(foundEntries)
        let categoryNamesById = makeCategoryNamesById(categories)

        NavigationStack {
            VStack(spacing: 0) {
                Picker("Вид", selection: $isCalendarShown) {
                    Text("Список").tag(false)
                    Text("Календарь").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                if isCalendarShown {
                    // Поиск и фильтр действуют и на календарь: можно смотреть по дням одну категорию.
                    JournalCalendar(today: today, entries: foundEntries, categories: categories)
                } else {
                    JournalList(groups: groups, categoryNamesById: categoryNamesById)
                }
            }
            .background(theme.background)
            .searchable(text: $query, prompt: "Найти по названию")
            .navigationTitle("Журнал")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    JournalFilterMenu(filter: $filter, categories: categories, accounts: accounts)
                }
            }
            .navigationDestination(for: JournalEntry.self) { entry in
                EntryDetailScreen(entry: entry)
            }
        }
    }
}

/// Записи по дням, новые сверху.
private struct JournalList: View {
    let groups: [DayGroup]
    let categoryNamesById: [String: String]

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.theme) private var theme

    var body: some View {
                List {
                    ForEach(groups) { group in
                        Section(formatDayWithWeekday(group.day)) {
                            ForEach(group.entries, id: \.id) { entry in
                                NavigationLink(value: entry) {
                                    JournalRow(
                                        entry: entry,
                                        categoryName: makeCategoryName(categoryId: entry.categoryId, namesById: categoryNamesById),
                                        isTimeShown: settingsStore.settings.shouldShowOperationTime,
                                        theme: theme
                                    )
                                }
                                .listRowBackground(theme.card)
                            }
                        }
                    }
                }
        .scrollContentBackground(.hidden)
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("Ничего не нашлось", systemImage: "magnifyingglass", description: Text("Измените поиск или фильтр."))
            }
        }
    }
}

/// Пустое поле — фильтр по нему не применяется.
struct JournalFilter: Equatable {
    var categoryId: String?
    var accountId: PersistentIdentifier?
    var sourceKind: SourceKind?

    var isActive: Bool {
        categoryId != nil || accountId != nil || sourceKind != nil
    }
}

/// Поиск без учёта регистра по названию и затем фильтр.
private func findEntries(_ entries: [JournalEntry], query: String, filter: JournalFilter) -> [JournalEntry] {
    let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
    return entries.filter { entry in
        let isTitleMatching = trimmedQuery.isEmpty || entry.title.localizedCaseInsensitiveContains(trimmedQuery)
        return isTitleMatching && isMatching(entry, filter: filter)
    }
}

private func isMatching(_ entry: JournalEntry, filter: JournalFilter) -> Bool {
    if let categoryId = filter.categoryId, entry.categoryId != categoryId {
        return false
    }
    // Перемещение видно в обоих счетах: и откуда, и куда.
    if let accountId = filter.accountId,
       entry.account?.persistentModelID != accountId,
       entry.counterAccount?.persistentModelID != accountId {
        return false
    }
    if let sourceKind = filter.sourceKind, !entry.sources.contains(where: { source in source.kind == sourceKind }) {
        return false
    }
    return true
}

// MARK: - Части экрана

struct JournalRow: View {
    let entry: JournalEntry
    let categoryName: String
    let isTimeShown: Bool
    let theme: Theme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(categoryName)
                    .font(.footnote)
                    .foregroundStyle(entry.categoryId == nil ? theme.warning : theme.secondaryText)
            }
            Spacer()
            EntryAmountAndTime(entry: entry, isTimeShown: isTimeShown, theme: theme)
        }
    }
}

private struct JournalFilterMenu: View {
    @Binding var filter: JournalFilter
    let categories: [SpendingCategory]
    let accounts: [Account]

    var body: some View {
        Menu {
            Picker("Категория", selection: $filter.categoryId) {
                Text("Все категории").tag(String?.none)
                ForEach(categories, id: \.id) { category in
                    Text(category.name).tag(String?.some(category.id))
                }
            }
            .pickerStyle(.menu)
            Picker("Счёт", selection: $filter.accountId) {
                Text("Все счета").tag(PersistentIdentifier?.none)
                ForEach(accounts, id: \.persistentModelID) { account in
                    Text(account.title).tag(PersistentIdentifier?.some(account.persistentModelID))
                }
            }
            .pickerStyle(.menu)
            Picker("Источник", selection: $filter.sourceKind) {
                Text("Все источники").tag(SourceKind?.none)
                ForEach(allSourceKinds, id: \.self) { kind in
                    Text(makeSourceKindTitle(kind)).tag(SourceKind?.some(kind))
                }
            }
            .pickerStyle(.menu)
            if filter.isActive {
                Button("Сбросить фильтр") {
                    filter = JournalFilter()
                }
            }
        } label: {
            Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }
}

private let allSourceKinds: [SourceKind] = [.statement, .applePay, .sms, .manual]
