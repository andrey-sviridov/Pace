import SwiftUI
import PaceCore

/// Четыре вкладки приложения (спека §8).
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
            JournalScreen(today: today)
                .tabItem { Label("Журнал", systemImage: "list.bullet") }
                .tag(MainTab.journal)
            AnalyticsScreen(today: today)
                .tabItem { Label("Аналитика", systemImage: "chart.bar") }
                .tag(MainTab.analytics)
            SettingsScreen(today: today)
                .tabItem { Label("Настройки", systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
        .tint(theme.accent)
    }
}

enum MainTab: Hashable {
    case home, journal, analytics, settings
}
