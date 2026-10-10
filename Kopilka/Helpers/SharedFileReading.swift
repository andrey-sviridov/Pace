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

/// Открытый через «Поделиться» файл iOS копирует к нам (Documents/Inbox, в новых iOS — tmp/<bundle id>-Inbox)
/// и сам не удаляет — копии копились бы. Файлы вне этих папок (например, выбранные в «Файлах») чужие, их не трогаем.
func deleteFileIfInInbox(url: URL, inboxDirectories: [URL]) throws {
    // /var и /private/var — один и тот же путь, поэтому сравниваем после раскрытия ссылок.
    let filePath = url.resolvingSymlinksInPath().standardizedFileURL.path
    let isInInbox = inboxDirectories.contains { directory in
        let directoryPath = directory.resolvingSymlinksInPath().standardizedFileURL.path
        return filePath.hasPrefix(directoryPath + "/")
    }
    guard isInInbox else { return }
    try FileManager.default.removeItem(at: url)
}
