import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import KopilkaCore

/// Вкладка «Настройки» (спека §8): оформление, период, импорт, источники, деньги, данные.
struct SettingsScreen: View {
    let today: CalendarDay

    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            List {
                AppearanceSection()
                ImportSection()
                SourcesSection()
                Section("Деньги") {
                    NavigationLink("Сверить остаток") { ReconcileScreen(today: today) }
                    NavigationLink("Правила") { RulesScreen() }
                }
                DataSection()
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("Настройки")
        }
    }
}

// MARK: - Оформление и период

private struct AppearanceSection: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(ErrorStore.self) private var errorStore

    var body: some View {
        Section("Оформление") {
            ThemeChooser(selection: settingsStore.settings.theme) { name in
                save(\.theme, name)
            }
            PeriodPicker(selection: Binding(
                get: { settingsStore.settings.periodMode },
                set: { mode in save(\.periodMode, mode) }
            ))
        }
    }

    private func save<Value>(_ field: ReferenceWritableKeyPath<AppSettings, Value>, _ value: Value) {
        do {
            try settingsStore.update(field, to: value)
        } catch {
            errorStore.show(error)
        }
    }
}

/// Три темы с мини-превью: фон, карточка и акцент — сразу видно, как будет выглядеть.
private struct ThemeChooser: View {
    let selection: ThemeName
    let onSelect: (ThemeName) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            ThemePreview(title: "A · Светлая", theme: Theme.make(.light, colorScheme: colorScheme), isSelected: selection == .light) {
                onSelect(.light)
            }
            ThemePreview(title: "B · Тёмная", theme: Theme.make(.dark, colorScheme: colorScheme), isSelected: selection == .dark) {
                onSelect(.dark)
            }
            ThemePreview(title: "C · Бумажная", theme: Theme.make(.paper, colorScheme: colorScheme), isSelected: selection == .paper) {
                onSelect(.paper)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ThemePreview: View {
    let title: String
    let theme: Theme
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.background)
                    .frame(height: 56)
                    .overlay(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.card)
                            .frame(height: 24)
                            .overlay(Capsule().fill(theme.accent).frame(width: 28, height: 6))
                            .padding(6)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? theme.accent : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 0.5)
                    )
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Импорт

private struct ImportSection: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(RulesStore.self) private var rulesStore
    @Environment(ErrorStore.self) private var errorStore

    @State private var employerName = ""

    var body: some View {
        Section {
            TextField("Работодатель", text: $employerName)
                .onSubmit(saveEmployer)
                .onAppear { employerName = settingsStore.settings.employerName }
            DatePicker(
                "На свою Kaspi до",
                selection: Binding(
                    get: { makeDate(day: settingsStore.settings.kaspiOwnCardUntil, calendar: .current) },
                    set: { date in saveKaspiCutoff(makeCalendarDay(date: date, calendar: .current)) }
                ),
                displayedComponents: .date
            )
        } header: {
            Text("Импорт")
        } footer: {
            Text("Поступления от работодателя считаются зарплатой и авансом. Переводы на другую карту раньше этой даты — перемещения на вашу Kaspi.")
        }
    }

    private func saveEmployer() {
        let trimmedName = employerName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            employerName = settingsStore.settings.employerName
            return
        }
        do {
            try settingsStore.update(\.employerName, to: trimmedName)
        } catch {
            errorStore.show(error)
        }
    }

    private func saveKaspiCutoff(_ day: CalendarDay) {
        do {
            try settingsStore.update(\.kaspiOwnCardUntil, to: day)
            try rulesStore.updateKaspiCutoff(day)
        } catch {
            errorStore.show(error)
        }
    }
}

// MARK: - Источники

private struct SourcesSection: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(ErrorStore.self) private var errorStore

    var body: some View {
        Section {
            LabeledContent("Выписка PDF", value: "всегда")
            Toggle("Apple Pay", isOn: makeToggle(\.isApplePayEnabled))
            Toggle("SMS Halyk", isOn: makeToggle(\.isSmsEnabled))
            Toggle("Показывать остаток после оплаты", isOn: makeToggle(\.shouldShowRemainingAfterPayment))
            NavigationLink("Как настроить «Команды»") { ShortcutsHelpScreen() }
        } header: {
            Text("Источники")
        } footer: {
            Text("Выключенный источник «Команды» молча пропускают: автоматизацию можно не удалять.")
        }
    }

    private func makeToggle(_ field: ReferenceWritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settingsStore.settings[keyPath: field] },
            set: { isOn in
                do {
                    try settingsStore.update(field, to: isOn)
                } catch {
                    errorStore.show(error)
                }
            }
        )
    }
}

// MARK: - Данные: резервная копия и «Начать заново»

private struct DataSection: View {
    @Environment(JournalStore.self) private var journalStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(ErrorStore.self) private var errorStore

    @State private var backupDocument: BackupDocument?
    @State private var isChoosingBackup = false
    @State private var restoreData: Data?
    @State private var isConfirmingReset = false
    @State private var isConfirmingResetAgain = false

    var body: some View {
        Section {
            Button("Сохранить резервную копию", action: prepareBackup)
            Button("Восстановить из копии") { isChoosingBackup = true }
            Button("Начать заново", role: .destructive) { isConfirmingReset = true }
        } header: {
            Text("Данные")
        } footer: {
            Text("Данные хранятся только на этом телефоне. Копия — единственный способ перенести их или вернуть после удаления приложения.")
        }
        .fileExporter(
            isPresented: makeIsShownBinding($backupDocument),
            document: backupDocument,
            contentType: .json,
            defaultFilename: "Копилка \(formatBackupDate(Date()))"
        ) { result in
            if case .failure(let error) = result { errorStore.show(error) }
        }
        .fileImporter(isPresented: $isChoosingBackup, allowedContentTypes: [.json]) { result in
            chooseBackup(result)
        }
        .confirmationDialog("Восстановить копию?", isPresented: makeIsShownBinding($restoreData), titleVisibility: .visible) {
            Button("Заменить всё копией", role: .destructive, action: restoreChosenBackup)
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Текущие операции, лимиты и настройки заменятся данными из файла.")
        }
        .confirmationDialog("Начать заново?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
            Button("Стереть всё", role: .destructive) { isConfirmingResetAgain = true }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Сотрутся операции, счета, лимиты, правила и настройки. Потом можно загрузить выписку с чистого листа.")
        }
        // Второе подтверждение — отдельным окном: стирание нельзя отменить.
        .alert("Точно стереть всё?", isPresented: $isConfirmingResetAgain) {
            Button("Стереть", role: .destructive, action: eraseEverything)
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Вернуть данные можно будет только из резервной копии.")
        }
    }

    private func prepareBackup() {
        do {
            backupDocument = BackupDocument(data: try journalStore.makeBackup())
        } catch {
            errorStore.show(error)
        }
    }

    private func chooseBackup(_ result: Result<URL, Error>) {
        do {
            restoreData = try readSharedFile(url: try result.get())
        } catch {
            errorStore.show(error)
        }
    }

    private func restoreChosenBackup() {
        guard let restoreData else { return }
        do {
            try journalStore.restoreBackup(restoreData)
            try settingsStore.reloadSettings()
        } catch {
            errorStore.show(error)
        }
    }

    /// После стирания настроек нет — корень увидит hasFinishedSetup == false и откроет начальную настройку.
    private func eraseEverything() {
        do {
            try journalStore.eraseAllData()
            try settingsStore.reloadSettings()
        } catch {
            errorStore.show(error)
        }
    }
}

/// Файл копии для системного «Сохранить в Файлы».
struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private func formatBackupDate(_ date: Date) -> String {
    date.formatted(.iso8601.year().month().day())
}
