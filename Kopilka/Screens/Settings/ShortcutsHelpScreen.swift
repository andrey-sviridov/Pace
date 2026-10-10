import SwiftUI

/// Пошаговая настройка автоматизаций «Команд» (спека §5.10). Только текст — ничего не меняет.
struct ShortcutsHelpScreen: View {
    @Environment(\.theme) private var theme

    var body: some View {
        List {
            Section("SMS от Halyk") {
                HelpStep(number: 1, text: "Подключите SMS-информирование в Halyk: банкомат, 7111 или отделение.")
                HelpStep(number: 2, text: "Откройте «Команды» → «Автоматизация» → «+» → «Сообщение».")
                HelpStep(number: 3, text: "Отправитель: Halyk. Выберите «Выполнять сразу».")
                HelpStep(number: 4, text: "Добавьте действие «Разобрать SMS Halyk» (Копилка) и передайте ему «Сообщение».")
                HelpStep(number: 5, text: "В настройках Копилки включите «SMS Halyk».")
            }
            Section("Apple Pay") {
                HelpStep(number: 1, text: "«Команды» → «Автоматизация» → «+» → «Транзакция».")
                HelpStep(number: 2, text: "Выберите карту Halyk и «Выполнять сразу».")
                HelpStep(number: 3, text: "Добавьте действие «Записать оплату в Копилку», передайте продавца, сумму и карту.")
                HelpStep(number: 4, text: "В настройках Копилки включите «Apple Pay».")
            }
            Section {
                Text("Если что-то не распознается, операция всё равно появится в «Проверьте новое», а выписка потом склеится с ней без дубля.")
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .navigationTitle("Как настроить")
    }
}

private struct HelpStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)").font(.headline.monospacedDigit())
            Text(text)
        }
    }
}
