import SwiftUI
import KopilkaCore

/// Четыре вкладки приложения (спека §8). Настройки пока заглушка (задача 17).
/// Вкладка и путь главной приходят сверху: итог импорта открывает «Проверьте новое» на главной.
struct MainTabView: View {
    let today: CalendarDay
    @Binding var selectedTab: MainTab
    @Binding var homePath: [HomeDestination]

    @Environment(\.theme) private var theme

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeScreen(today: today, path: $homePath)
                .tabItem { Label("Главная", systemImage: "house") }
                .tag(MainTab.home)
            JournalScreen()
                .tabItem { Label("Журнал", systemImage: "list.bullet") }
                .tag(MainTab.journal)
            AnalyticsScreen(today: today)
                .tabItem { Label("Аналитика", systemImage: "chart.bar") }
                .tag(MainTab.analytics)
            PlaceholderScreen(title: "Настройки", text: "Тема, период, источники.")
                .tabItem { Label("Настройки", systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
        .tint(theme.accent)
    }
}

enum MainTab: Hashable {
    case home, journal, analytics, settings
}
