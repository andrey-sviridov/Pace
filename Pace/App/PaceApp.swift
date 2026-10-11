import SwiftUI
import SwiftData
import PaceCore

@main
struct PaceApp: App {
    // Всё общее состояние создаётся здесь, один раз, и уходит вниз через .environment.
    @State private var startup = makeAppStartup()

    var body: some Scene {
        WindowGroup {
            Group {
                switch startup {
                case .ready(let stores):
                    RootView()
                        .environment(stores.errorStore)
                        .environment(stores.settingsStore)
                        .environment(stores.journalStore)
                        .environment(stores.accountStore)
                        .environment(stores.rulesStore)
                        .modelContainer(stores.container)
                case .failed(let message):
                    StartupErrorScreen(message: message)
                }
            }
            // Один размер текста на всё приложение: системный шаг меньше обычного.
            // Обычный текст становится 15 pt, подписи и заголовки уменьшаются в той же пропорции.
            .dynamicTypeSize(.small)
        }
    }
}

/// База открылась — работаем; не открылась — показываем причину вместо падения.
enum AppStartup {
    case ready(AppStores)
    case failed(message: String)
}

struct AppStores {
    let container: ModelContainer
    let errorStore: ErrorStore
    let settingsStore: SettingsStore
    let journalStore: JournalStore
    let accountStore: AccountStore
    let rulesStore: RulesStore
}

func makeAppStartup() -> AppStartup {
    do {
        let container = try makeModelContainer(inMemory: false)
        let context = container.mainContext
        let stores = AppStores(
            container: container,
            errorStore: ErrorStore(),
            settingsStore: try SettingsStore(context: context),
            journalStore: JournalStore(context: context),
            accountStore: AccountStore(context: context),
            rulesStore: try RulesStore(context: context)
        )
        return .ready(stores)
    } catch {
        return .failed(message: makeErrorMessage(error))
    }
}
