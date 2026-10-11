import Foundation

/// Ошибки начальной настройки (спека §5.9); тексты для пользователя — в `makeErrorMessage`.
enum SetupError: Error {
    /// Шаг 2 подставляет остаток выписки как остаток карты — выписка депозита сюда не подходит.
    case historyIsNotCardStatement
    /// Импорт истории только что завёл этот счёт; если его нет — база в неожиданном состоянии.
    case statementAccountNotFound(number: String)
}
