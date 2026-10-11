import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PaceCore

/// Вкладка «Настройки» (спека §8): оформление, период, источники, счета и правила, данные.
struct SettingsScreen: View {
    let today: CalendarDay

    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            List {
                AppearanceSection()
                PeriodSection()
                SourcesSection()
                Section("Счета и правила") {
                    NavigationLink("Мои счета") { AccountsScreen(today: today) }
                    NavigationLink("Правила категорий") { RulesScreen() }
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
                do {
                    try settingsStore.update(\.theme, to: name)
                } catch {
                    errorStore.show(error)
                }
            }
        }
    }
}

private struct PeriodSection: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(ErrorStore.self) private var errorStore

    var body: some View {
        Section {
            PeriodPicker(selection: makeBinding(\.periodMode))
            Toggle("Получаю аванс", isOn: makeBinding(\.hasAdvance))
            Toggle("Показывать время операций", isOn: makeBinding(\.shouldShowOperationTime))
        } header: {
            Text("Месяц считается")
        } footer: {
            Text(settingsStore.settings.hasAdvance
                 ? "Главная показывает, сколько можно потратить до ближайшего поступления — аванса или зарплаты, а месяц целиком — строкой ниже."
                 : "Главная показывает, сколько можно потратить до конца месяца.")
        }
    }

    private func makeBinding<Value>(_ field: ReferenceWritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: field] },
            set: { value in
                do {
                    try settingsStore.update(field, to: value)
                } catch {
                    errorStore.show(error)
                }
            }
        )
    }
}

/// Пять тем с мини-превью: фон, карточка и акцент — сразу видно, как будет выглядеть.
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
            ThemePreview(title: "D · Графит", theme: Theme.make(.graphite, colorScheme: colorScheme), isSelected: selection == .graphite) {
                onSelect(.graphite)
            }
            ThemePreview(title: "E · Свечение", theme: Theme.make(.glow, colorScheme: colorScheme), isSelected: selection == .glow) {
                onSelect(.glow)
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

// MARK: - Данные: загрузка выписки и «Начать заново»

private struct DataSection: View {
    @Environment(JournalStore.self) private var journalStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(ErrorStore.self) private var errorStore
    @Environment(\.importStatementFile) private var importStatementFile

    @State private var isChoosingStatement = false
    @State private var isConfirmingReset = false
    @State private var isConfirmingResetAgain = false

    var body: some View {
        Section {
            Button("Загрузить выписку PDF") { isChoosingStatement = true }
            Button("Начать заново", role: .destructive) { isConfirmingReset = true }
        } header: {
            Text("Данные")
        } footer: {
            Text("Выписку можно загружать сколько угодно раз: уже известные операции пропускаются, ваши правки не затираются.")
        }
        .fileImporter(isPresented: $isChoosingStatement, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url): importStatementFile(url)
            case .failure(let error): errorStore.show(error)
            }
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
            Text("Вернуть данные будет нельзя.")
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
