import SwiftUI

/// Четыре вкладки приложения (спека §8). Пока экраны — заглушки, их заменят задачи 13–17.
struct MainTabView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        TabView {
            PlaceholderScreen(title: "Главная", text: "Сколько можно потратить до зарплаты.")
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
