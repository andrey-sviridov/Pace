import SwiftUI
import SwiftData
import KopilkaCore

/// Карточка записи: поля пользователя (название, категория, заметка), источники с сырыми данными
/// и «Это та же операция, что…» для ручной склейки (спека §5.6). Удаления нет.
struct EntryDetailScreen: View {
    let entry: JournalEntry

    @Environment(JournalStore.self) private var journalStore
    @Environment(ErrorStore.self) private var errorStore
    @Environment(\.theme) private var theme

    @Query private var entries: [JournalEntry]
    @Query(sort: \SpendingCategory.sortOrder) private var categories: [SpendingCategory]
    @Query private var merchantRules: [MerchantRule]

    @State private var draftTitle: String
    @State private var draftNote: String
    @State private var isPickingCategory = false
    @State private var isPickingSameEntry = false

    init(entry: JournalEntry) {
        self.entry = entry
        _draftTitle = State(initialValue: entry.title)
        _draftNote = State(initialValue: entry.note)
    }

    var body: some View {
        let categoryName = makeCategoryName(categoryId: entry.categoryId, namesById: makeCategoryNamesById(categories))
        let hasUnsavedText = draftTitle != entry.title || draftNote != entry.note

        Form {
            Section {
                TextField("Название", text: $draftTitle)
                Button {
                    isPickingCategory = true
                } label: {
                    LabeledContent("Категория", value: categoryName)
                }
                TextField("Заметка", text: $draftNote, axis: .vertical)
            }
            .listRowBackground(theme.card)

            EntryFactsSection(entry: entry, theme: theme)
            EntrySourcesSection(sources: entry.sources, theme: theme)

            Section {
                Button("Это та же операция, что…") {
                    isPickingSameEntry = true
                }
            } footer: {
                Text("Источники выбранной записи перейдут в эту, а выбранная скроется из журнала.")
            }
            .listRowBackground(theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить", action: saveText)
                    .disabled(!hasUnsavedText)
            }
        }
        .sheet(isPresented: $isPickingCategory) {
            CategoryPicker(categories: categories, selectedId: entry.categoryId) { categoryId in
                updateCategory(categoryId)
            }
        }
        .sheet(isPresented: $isPickingSameEntry) {
            SameEntryPicker(
                candidates: findMergeCandidates(for: entry, among: entries, windowDays: 3),
                theme: theme,
                onMerge: { candidate in merge(candidate) }
            )
        }
    }

    /// Правка категории не меняет название в правиле: берём то, что там уже было.
    private func updateCategory(_ categoryId: String) {
        let existingRule = merchantRules.first { rule in rule.merchantKey == entry.merchantKey }
        do {
            try saveUserEdit(entry, title: entry.title, categoryId: categoryId, ruleTitle: existingRule?.title, journalStore: journalStore)
        } catch {
            errorStore.show(error)
        }
    }

    private func saveText() {
        let title = draftTitle.trimmingCharacters(in: .whitespaces)
        do {
            if !title.isEmpty, title != entry.title {
                try saveUserEdit(entry, title: title, categoryId: entry.categoryId, ruleTitle: title, journalStore: journalStore)
            }
            if draftNote != entry.note {
                try journalStore.updateNote(entry, note: draftNote)
            }
        } catch {
            errorStore.show(error)
        }
        // Пустое название не сохраняем — возвращаем прежнее в поле.
        draftTitle = entry.title
    }

    private func merge(_ candidate: JournalEntry) {
        do {
            try journalStore.mergeEntries(keep: entry, remove: candidate)
        } catch {
            errorStore.show(error)
        }
    }
}

// MARK: - Части экрана

private struct EntryFactsSection: View {
    let entry: JournalEntry
    let theme: Theme

    var body: some View {
        Section("Операция") {
            LabeledContent("Дата", value: formatDayWithWeekday(entry.day))
            LabeledContent("Сумма") {
                EntryAmountText(amount: entry.amount, type: entry.type)
            }
            if entry.feeAmount > 0 {
                LabeledContent("Комиссия", value: formatTenge(entry.feeAmount))
            }
            if let account = entry.account {
                LabeledContent("Счёт", value: account.title)
            }
            if let counterAccount = entry.counterAccount {
                LabeledContent("Куда", value: counterAccount.title)
            }
        }
        .listRowBackground(theme.card)
    }
}

/// Сырые данные каждого источника — как пришли из выписки, Apple Pay или SMS. Только чтение.
private struct EntrySourcesSection: View {
    let sources: [SourceRecord]
    let theme: Theme

    var body: some View {
        let sortedSources = sources.sorted { first, second in first.receivedAt < second.receivedAt }
        Section("Источники") {
            ForEach(sortedSources, id: \.key) { source in
                SourceRow(source: source, theme: theme)
            }
        }
        .listRowBackground(theme.card)
    }
}

private struct SourceRow: View {
    let source: SourceRecord
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(makeSourceKindTitle(source.kind)) · \(makeSourceTimeText(source))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.text)
            if let rawText = source.rawDescription ?? source.rawText {
                Text(rawText)
                    .font(.footnote.monospaced())
                    .foregroundStyle(theme.text)
                    .textSelection(.enabled)
            }
            ForEach(makeSourceAmountLines(source), id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(theme.secondaryText)
            }
            if let cardOrAccount = source.cardOrAccount, !cardOrAccount.isEmpty {
                Text(cardOrAccount)
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SameEntryPicker: View {
    let candidates: [JournalEntry]
    let theme: Theme
    let onMerge: (JournalEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var chosenCandidate: JournalEntry?

    var body: some View {
        NavigationStack {
            List(candidates, id: \.id) { candidate in
                Button {
                    chosenCandidate = candidate
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.title)
                                .foregroundStyle(theme.text)
                            Text(formatDayWithWeekday(candidate.day))
                                .font(.footnote)
                                .foregroundStyle(theme.secondaryText)
                        }
                        Spacer()
                        EntryAmountText(amount: candidate.amount, type: candidate.type)
                    }
                }
            }
            .overlay {
                if candidates.isEmpty {
                    ContentUnavailableView("Нет похожих записей", systemImage: "equal.circle", description: Text("Ищем записи с той же суммой в пределах трёх дней."))
                }
            }
            // Подтверждение внутри sheet: окно поверх закрывающегося sheet SwiftUI не показывает.
            .confirmationDialog(
                "Объединить записи?",
                isPresented: makeIsShownBinding($chosenCandidate),
                titleVisibility: .visible,
                presenting: chosenCandidate
            ) { candidate in
                Button("Объединить") {
                    onMerge(candidate)
                    dismiss()
                }
                Button("Отмена", role: .cancel) {}
            } message: { candidate in
                Text("«\(candidate.title)» · \(formatTenge(candidate.amount)) · \(formatShortDay(candidate.day)) скроется, а её источники перейдут в эту запись.")
            }
            .navigationTitle("Та же операция")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}

/// Выписка — дни операции и проведения; Apple Pay и SMS — точное время прихода.
private func makeSourceTimeText(_ source: SourceRecord) -> String {
    switch source.kind {
    case .statement:
        let operationText = source.operationDay.map { day in formatDay(day) } ?? "—"
        guard let processingDay = source.processingDay, processingDay != source.operationDay else { return operationText }
        return "\(operationText), проведено \(formatDay(processingDay))"
    case .applePay, .sms, .manual:
        return source.receivedAt.formatted(
            .dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "ru_RU"))
        )
    }
}

/// Только суммы, которые есть в источнике: «Сумма 10 USD», «Расход 5 000 ₸», «Комиссия 200 ₸».
private func makeSourceAmountLines(_ source: SourceRecord) -> [String] {
    var lines: [String] = []
    if let operationAmount = source.operationAmount {
        let currency = source.currency ?? "KZT"
        lines.append("Сумма операции \(operationAmount.formatted(.number.locale(Locale(identifier: "ru_RU")))) \(currency)")
    }
    if let incomeAmount = source.incomeAmount, incomeAmount > 0 {
        lines.append("Приход \(formatTenge(incomeAmount))")
    }
    if let expenseAmount = source.expenseAmount, expenseAmount > 0 {
        lines.append("Расход \(formatTenge(expenseAmount))")
    }
    if let feeAmount = source.feeAmount, feeAmount > 0 {
        lines.append("Комиссия \(formatTenge(feeAmount))")
    }
    return lines
}
