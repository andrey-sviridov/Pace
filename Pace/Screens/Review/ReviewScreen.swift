import SwiftUI
import SwiftData
import PaceCore

/// «Проверьте новое» (спека §8): непроверенные записи по дням, правка названия и категории,
/// «Объединить» для возможных дублей, «Всё ок → в журнал». Удаления нет.
struct ReviewScreen: View {
    @Environment(JournalStore.self) private var journalStore
    @Environment(ErrorStore.self) private var errorStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.theme) private var theme

    // Предикат отсекает проверенные в базе; окончательное правило — isAwaitingReview из ядра.
    @Query(filter: #Predicate<JournalEntry> { entry in entry.isReviewed == false }) private var notReviewedEntries: [JournalEntry]
    @Query(sort: \SpendingCategory.sortOrder) private var categories: [SpendingCategory]
    @Query private var merchantRules: [MerchantRule]

    @State private var categoryEntry: JournalEntry?
    @State private var titleEntry: JournalEntry?
    @State private var draftTitle = ""
    @State private var mergeEntry: JournalEntry?

    var body: some View {
        let awaitingEntries = notReviewedEntries.filter { entry in isAwaitingReview(entry) }
        let groups = makeDayGroups(awaitingEntries)
        let categoryNamesById = makeCategoryNamesById(categories)

        List {
            ForEach(groups) { group in
                Section(formatDayWithWeekday(group.day)) {
                    ForEach(group.entries, id: \.id) { entry in
                        ReviewRow(
                            entry: entry,
                            categoryName: makeCategoryName(categoryId: entry.categoryId, namesById: categoryNamesById),
                            isTimeShown: settingsStore.settings.shouldShowOperationTime,
                            theme: theme,
                            onEditTitle: { showTitleEditor(entry) },
                            onPickCategory: { categoryEntry = entry },
                            onMerge: { mergeEntry = entry }
                        )
                        .listRowBackground(theme.card)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("Всё проверено", systemImage: "checkmark.circle", description: Text("Новые операции появятся после загрузки выписки."))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !groups.isEmpty {
                ReviewDoneButton(count: awaitingEntries.count, theme: theme, onTap: markAllReviewed)
            }
        }
        .navigationTitle("Проверьте новое")
        .sheet(item: $categoryEntry) { entry in
            CategoryPicker(categories: categories, selectedId: entry.categoryId) { categoryId in
                updateCategory(entry, categoryId: categoryId)
            }
        }
        .alert("Название", isPresented: makeIsShownBinding($titleEntry), presenting: titleEntry) { entry in
            TextField("Название", text: $draftTitle)
            Button("Сохранить") { updateTitle(entry) }
            Button("Отмена", role: .cancel) {}
        } message: { entry in
            Text(makeRenameMessage(entry))
        }
        .confirmationDialog(
            "Объединить с похожей записью?",
            isPresented: makeIsShownBinding($mergeEntry),
            titleVisibility: .visible,
            presenting: mergeEntry
        ) { entry in
            Button("Объединить") { mergeWithCandidate(entry) }
            Button("Отмена", role: .cancel) {}
        } message: { entry in
            Text(makeMergeMessage(entry))
        }
    }

    private func showTitleEditor(_ entry: JournalEntry) {
        draftTitle = entry.title
        titleEntry = entry
    }

    /// Правка категории не меняет название в правиле: берём то, что там уже было.
    private func updateCategory(_ entry: JournalEntry, categoryId: String) {
        let existingRule = merchantRules.first { rule in rule.merchantKey == entry.merchantKey }
        do {
            try journalStore.updateEntry(entry, title: entry.title, categoryId: categoryId)
            // У переводов продавца нет (пустой ключ) — стор правило не пишет и возвращает nil.
            guard let rule = try journalStore.saveMerchantRule(merchantKey: entry.merchantKey, categoryId: categoryId, title: existingRule?.title) else { return }
            try journalStore.applyRuleToUnreviewed(rule)
        } catch {
            errorStore.show(error)
        }
    }

    private func updateTitle(_ entry: JournalEntry) {
        let title = draftTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, title != entry.title else { return }
        do {
            try journalStore.updateEntry(entry, title: title, categoryId: entry.categoryId)
            // Категория ещё не выбрана (переименовали неизвестную покупку) — правилу нечего запомнить,
            // а подставленная за пользователя категория сделала бы следующие покупки продавца проверенными.
            guard let categoryId = entry.categoryId else { return }
            guard let rule = try journalStore.saveMerchantRule(merchantKey: entry.merchantKey, categoryId: categoryId, title: title) else { return }
            try journalStore.applyRuleToUnreviewed(rule)
        } catch {
            errorStore.show(error)
        }
    }

    /// Остаётся прежняя запись (кандидат), новая-дубль скрывается и отдаёт ей свои источники.
    /// Кандидат мог уже сам уйти в другую запись — тогда объединяем с той, что видна в журнале.
    private func mergeWithCandidate(_ entry: JournalEntry) {
        guard let candidate = entry.possibleDuplicateOf else { return }
        let keptEntry = findMergeRoot(candidate)
        do {
            try journalStore.mergeEntries(keep: keptEntry, remove: entry)
        } catch {
            errorStore.show(error)
        }
    }

    private func markAllReviewed() {
        do {
            try journalStore.markAllReviewed()
        } catch {
            errorStore.show(error)
        }
    }
}

// MARK: - Части экрана

private struct ReviewRow: View {
    let entry: JournalEntry
    let categoryName: String
    let isTimeShown: Bool
    let theme: Theme
    let onEditTitle: () -> Void
    let onPickCategory: () -> Void
    let onMerge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Button(action: onEditTitle) {
                    HStack(spacing: 4) {
                        Text(entry.title)
                            .foregroundStyle(theme.text)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                Spacer()
                EntryAmountAndTime(entry: entry, isTimeShown: isTimeShown, theme: theme)
            }
            VStack(alignment: .leading, spacing: 6) {
                Button(action: onPickCategory) {
                    Text(categoryName)
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .foregroundStyle(entry.categoryId == nil ? theme.warning : theme.accent)
                        .background(theme.track, in: Capsule())
                }
                if entry.possibleDuplicateOf != nil {
                    PossibleDuplicateBadge(theme: theme, onMerge: onMerge)
                }
            }
        }
        // Несколько кнопок в строке списка: без этого стиля строка ловит нажатие целиком.
        .buttonStyle(.borderless)
        .padding(.vertical, 2)
    }
}

private struct PossibleDuplicateBadge: View {
    let theme: Theme
    let onMerge: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("возможный дубль")
                .font(.footnote)
                .foregroundStyle(theme.warning)
            Button("Объединить", action: onMerge)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.accent)
        }
    }
}

private struct ReviewDoneButton: View {
    let count: Int
    let theme: Theme
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text("Всё ок → в журнал · \(count)")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.accent)
        .padding()
        .background(theme.background)
    }
}

/// С какой записью объединяем: «Останется «Magnum» · 1 500 ₸ · 12 окт. …».
private func makeMergeMessage(_ entry: JournalEntry) -> String {
    guard let candidate = entry.possibleDuplicateOf else { return "" }
    let keptEntry = findMergeRoot(candidate)
    let amountText = formatSignedTenge(keptEntry.amount, type: keptEntry.type)
    return "Останется «\(keptEntry.title)» · \(amountText) · \(formatShortDay(keptEntry.day)). Источники этой записи перейдут в неё."
}

/// Правило пишется только у продавца с выбранной категорией — иначе меняется одна запись.
private func makeRenameMessage(_ entry: JournalEntry) -> String {
    let willSaveRule = !entry.merchantKey.isEmpty && entry.categoryId != nil
    return willSaveRule ? "Новое название запомнится для этого продавца." : "Название изменится только у этой записи."
}
