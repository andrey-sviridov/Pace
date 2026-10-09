import SwiftUI
import KopilkaCore

/// Корень интерфейса: тема из настроек, вкладки (или начальная настройка), открытие PDF и окно ошибки.
struct RootView: View {
    @Environment(ErrorStore.self) private var errorStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(JournalStore.self) private var journalStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var importResult: ImportResult?

    var body: some View {
        @Bindable var errorStore = errorStore
        let themeName = settingsStore.settings.theme

        RootContent(hasFinishedSetup: settingsStore.settings.hasFinishedSetup)
            .environment(\.theme, Theme.make(themeName, colorScheme: colorScheme))
            // Тема B тёмная всегда, поэтому и системные элементы (вкладки, окна) переводим в тёмный режим.
            .preferredColorScheme(themeName == .dark ? .dark : nil)
            .onOpenURL { url in
                openStatement(url: url)
            }
            .sheet(isPresented: makeIsShownBinding($importResult)) {
                ImportResultSheet(result: importResult, onReview: closeImportResult)
                    .environment(\.theme, Theme.make(themeName, colorScheme: colorScheme))
            }
            .alert("Не получилось", isPresented: makeIsShownBinding($errorStore.currentMessage)) {
                Button("Понятно") { errorStore.close() }
            } message: {
                Text(errorStore.currentMessage ?? "")
            }
    }

    /// «Поделиться → Копилка»: сразу импорт и экран итога (спека §8).
    private func openStatement(url: URL) {
        do {
            let pdfData = try readSharedFile(url: url)
            importResult = try journalStore.importStatement(data: pdfData, mode: .regular)
        } catch {
            errorStore.show(error)
        }
    }

    // Переход в «Проверьте новое» появится вместе с этим экраном (задача 14), пока просто закрываем итог.
    private func closeImportResult() {
        importResult = nil
    }
}

/// Пока начальная настройка не пройдена, вкладкам нечего показывать.
private struct RootContent: View {
    let hasFinishedSetup: Bool

    var body: some View {
        if hasFinishedSetup {
            MainTabView()
        } else {
            PlaceholderScreen(title: "Начальная настройка", text: "Здесь будет загрузка первой выписки и остатки счетов.")
        }
    }
}

/// Содержимое sheet вычисляется и в момент закрытия, когда результата уже нет.
private struct ImportResultSheet: View {
    let result: ImportResult?
    let onReview: () -> Void

    var body: some View {
        if let result {
            ImportResultScreen(result: result, onReview: onReview)
        }
    }
}
