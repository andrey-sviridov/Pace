import SwiftUI
import PaceCore

/// Корень интерфейса: тема из настроек, вкладки (или начальная настройка), открытие PDF и окно ошибки.
struct RootView: View {
    @Environment(ErrorStore.self) private var errorStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(JournalStore.self) private var journalStore
    @Environment(AccountStore.self) private var accountStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    /// «Сегодня» для всех расчётов считается только здесь и обновляется, когда приложение снова на экране.
    @State private var today = makeCalendarDay(date: .now, calendar: .current)

    @State private var importResult: ImportResult?
    /// Файл, пришедший через «Поделиться» до конца настройки: его забирает экран настройки.
    @State private var setupPdfData: Data?
    @State private var unknownAccountImport: UnknownAccountImport?
    @State private var selectedTab = MainTab.home
    @State private var homePath: [HomeDestination] = []

    var body: some View {
        @Bindable var errorStore = errorStore
        let themeName = settingsStore.settings.theme

        RootContent(
            hasFinishedSetup: settingsStore.settings.hasFinishedSetup,
            today: today,
            setupPdfData: $setupPdfData,
            selectedTab: $selectedTab,
            homePath: $homePath
        )
            .environment(\.theme, Theme.make(themeName, colorScheme: colorScheme))
            // Тема B тёмная всегда, поэтому и системные элементы (вкладки, окна) переводим в тёмный режим.
            .preferredColorScheme(themeName == .dark ? .dark : nil)
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                today = makeCalendarDay(date: .now, calendar: .current)
            }
            .onOpenURL { url in
                openSharedFile(url: url)
            }
            // Кнопка «Загрузить выписку» в настройках идёт тем же путём, что и «Поделиться».
            .environment(\.importStatementFile, openSharedFile)
            .confirmationDialog(
                "Неизвестный счёт \(unknownAccountImport?.accountNumber ?? "")",
                isPresented: makeIsShownBinding($unknownAccountImport),
                titleVisibility: .visible,
                presenting: unknownAccountImport
            ) { pending in
                Button("Карта") { addAccountAndImport(kind: .card, pending: pending) }
                Button("Депозит") { addAccountAndImport(kind: .deposit, pending: pending) }
                Button("Другая своя карта") { addAccountAndImport(kind: .ownOtherCard, pending: pending) }
                Button("Отмена", role: .cancel) {}
            } message: { pending in
                Text("Такого счёта ещё нет в приложении. Добавить его и загрузить выписку?")
            }
            .sheet(isPresented: makeIsShownBinding($importResult)) {
                ImportResultSheet(result: importResult, onReview: openReview)
                    .environment(\.theme, Theme.make(themeName, colorScheme: colorScheme))
            }
            .alert("Не получилось", isPresented: makeIsShownBinding($errorStore.currentMessage)) {
                Button("Понятно") { errorStore.close() }
            } message: {
                Text(errorStore.currentMessage ?? "")
            }
    }

    /// «Поделиться → Pace»: до конца настройки файл уходит в настройку, после — сразу импорт и итог (спека §8).
    private func openSharedFile(url: URL) {
        let pdfData: Data
        do {
            pdfData = try readSharedFile(url: url)
        } catch {
            errorStore.show(error)
            return
        }
        deleteInboxCopy(url: url)

        guard settingsStore.settings.hasFinishedSetup else {
            setupPdfData = pdfData
            return
        }
        importSharedStatement(pdfData: pdfData)
    }

    private func deleteInboxCopy(url: URL) {
        do {
            // tmp целиком наш: туда система кладёт только копии пришедших файлов.
            let inboxDirectories = [URL.documentsDirectory.appending(path: "Inbox"), URL.temporaryDirectory]
            try deleteFileIfInInbox(url: url, inboxDirectories: inboxDirectories)
        } catch {
            errorStore.show(error)
        }
    }

    /// Данные файла держим до ответа на «Неизвестный счёт»: файл в Inbox уже удалён, повтор идёт из памяти.
    /// Возвращает шапку загруженной выписки; не загрузилась — nil (ошибка или вопрос уже показаны).
    private func importSharedStatement(pdfData: Data) {
        do {
            let statement = try journalStore.readStatement(pdfData: pdfData)
            importResult = try journalStore.importStatement(statement, mode: .regular)
        } catch ImportError.unknownAccount(let number) {
            unknownAccountImport = UnknownAccountImport(accountNumber: number, pdfData: pdfData)
        } catch {
            errorStore.show(error)
        }
    }

    /// Точку отсчёта нового счёта ставит сам импорт (остаток из шапки выписки на дату формирования).
    private func addAccountAndImport(kind: AccountKind, pending: UnknownAccountImport) {
        do {
            let title = makeNewAccountTitle(kind: kind, accountNumber: pending.accountNumber)
            _ = try accountStore.addAccount(kind: kind, title: title, number: pending.accountNumber)
        } catch {
            errorStore.show(error)
            return
        }
        importSharedStatement(pdfData: pending.pdfData)
    }

    /// «Проверить» в итоге импорта: главная, поверх неё «Проверьте новое».
    private func openReview() {
        importResult = nil
        selectedTab = .home
        homePath = [.review]
    }
}

/// Пока начальная настройка не пройдена, вкладкам нечего показывать.
private struct RootContent: View {
    let hasFinishedSetup: Bool
    let today: CalendarDay
    @Binding var setupPdfData: Data?
    @Binding var selectedTab: MainTab
    @Binding var homePath: [HomeDestination]

    var body: some View {
        if hasFinishedSetup {
            MainTabView(today: today, selectedTab: $selectedTab, homePath: $homePath)
        } else {
            OnboardingScreen(sharedPdfData: $setupPdfData)
        }
    }
}

/// Выписка по счёту, которого нет в базе: ждёт ответа пользователя, чей это счёт.
private struct UnknownAccountImport {
    let accountNumber: String
    let pdfData: Data
}

/// Номер в выписке — IBAN счёта; для узнавания хватает последних четырёх цифр.
private func makeNewAccountTitle(kind: AccountKind, accountNumber: String) -> String {
    let lastDigits = accountNumber.suffix(4)
    switch kind {
    case .card:
        return "Карта *\(lastDigits)"
    case .deposit:
        return "Депозит"
    case .ownOtherCard:
        return "Своя карта *\(lastDigits)"
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
