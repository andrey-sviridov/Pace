import Foundation

/// Файл из «Поделиться» может лежать вне песочницы приложения: без security-scoped доступа его не прочитать.
/// Если система уже скопировала файл к нам (Inbox), доступ не нужен и start вернёт false — это не ошибка.
func readSharedFile(url: URL) throws -> Data {
    let isAccessGranted = url.startAccessingSecurityScopedResource()
    defer {
        if isAccessGranted {
            url.stopAccessingSecurityScopedResource()
        }
    }
    return try Data(contentsOf: url)
}
