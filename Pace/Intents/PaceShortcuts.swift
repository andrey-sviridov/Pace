import AppIntents

/// Действия Pace в приложении «Команды» — их выбирают в автоматизациях «Транзакция» и «Сообщение».
struct PaceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordApplePayIntent(),
            phrases: ["Записать оплату в \(.applicationName)"],
            shortTitle: "Записать оплату",
            systemImageName: "creditcard"
        )
        AppShortcut(
            intent: ParseSmsIntent(),
            phrases: ["Разобрать SMS Halyk в \(.applicationName)"],
            shortTitle: "Разобрать SMS Halyk",
            systemImageName: "message"
        )
    }
}
