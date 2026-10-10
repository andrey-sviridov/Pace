import SwiftUI
import KopilkaCore

/// Выбор категории: группы по виду, поиск по названию. Открывается в sheet;
/// после выбора отдаёт id через `onSelect` и закрывается сам.
struct CategoryPicker: View {
    let categories: [SpendingCategory]
    let selectedId: String?
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var query = ""

    var body: some View {
        let groups = makeCategoryGroups(categories: categories, query: query)

        NavigationStack {
            List {
                ForEach(groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.categories, id: \.id) { category in
                            CategoryPickerRow(category: category, isSelected: category.id == selectedId, theme: theme) {
                                onSelect(category.id)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Найти категорию")
            .navigationTitle("Категория")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}

private struct CategoryPickerRow: View {
    let category: SpendingCategory
    let isSelected: Bool
    let theme: Theme
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: category.iconName)
                    .foregroundStyle(theme.accent)
                    .frame(width: 28)
                Text(category.name)
                    .foregroundStyle(theme.text)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(theme.accent)
                }
            }
        }
    }
}

private struct CategoryGroup {
    let title: String
    let categories: [SpendingCategory]
}

/// Обязательные → гибкие → доход → перемещения; пустые после поиска группы не показываем.
private func makeCategoryGroups(categories: [SpendingCategory], query: String) -> [CategoryGroup] {
    let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
    let foundCategories = trimmedQuery.isEmpty
        ? categories
        : categories.filter { category in category.name.localizedCaseInsensitiveContains(trimmedQuery) }
    let sortedCategories = foundCategories.sorted { first, second in first.sortOrder < second.sortOrder }

    let kinds: [(kind: CategoryKind, title: String)] = [
        (.obligatory, "Обязательные"),
        (.flexible, "Гибкие"),
        (.income, "Доход"),
        (.transfer, "Перемещения"),
    ]
    let groups = kinds.map { item in
        CategoryGroup(title: item.title, categories: sortedCategories.filter { category in category.kind == item.kind })
    }
    return groups.filter { group in !group.categories.isEmpty }
}
