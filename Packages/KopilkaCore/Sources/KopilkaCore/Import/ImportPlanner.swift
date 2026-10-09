/// Строки файла, которых ещё нет в базе: порядок файла сохраняется.
public func findNewRows(keyedRows: [KeyedRow], existingKeys: Set<String>) -> [KeyedRow] {
    keyedRows.filter { keyed in !existingKeys.contains(keyed.key) }
}
