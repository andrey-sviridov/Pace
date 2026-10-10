import SwiftUI
import KopilkaCore

/// Четыре вкладки приложения (спека §8). Журнал, аналитика и настройки пока заглушки (задачи 14, 16, 17).
struct MainTabView: View {
    let today: CalendarDay

    @Environment(\.theme) private var theme

    var body: some View {
        TabView {
            HomeScreen(today: today)
                .tabItem { Label("Главная", systemImage: "house") }
            PlaceholderScreen(title: "Журнал", text: "Все операции по дням.")
                .tabItem { Label("Журнал", systemImage: "list.bullet") }
            PlaceholderScreen(title: "Аналитика", text: "Куда уходят деньги.")
                .tabItem { Label("Аналитика", systemImage: "chart.bar") }
            PlaceholderScreen(title: "Настройки", text: "Тема, период, источники.")
                .tabItem { Label("Настройки", systemImage: "gearshape") }
        }
        .tint(theme.accent)
    }
}
