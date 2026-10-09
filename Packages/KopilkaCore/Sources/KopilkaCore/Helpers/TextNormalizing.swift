import Foundation

/// Описание операции для сравнения: без пробелов и переводов строк, в верхнем регистре.
public func normalizeDescription(_ text: String) -> String {
    // PDF переносит длинные описания по строкам в произвольных местах, поэтому убираем все пробельные символы.
    let withoutWhitespace = text.filter { character in !character.isWhitespace }
    return withoutWhitespace.uppercased()
}
