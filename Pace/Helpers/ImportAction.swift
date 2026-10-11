import SwiftUI

extension EnvironmentValues {
    /// Загрузка выписки из файла тем же путём, что и «Поделиться → Pace»: итог, вопрос о неизвестном счёте, ошибки.
    /// Задаёт корень приложения (RootView).
    @Entry var importStatementFile: (URL) -> Void = { _ in }
}
