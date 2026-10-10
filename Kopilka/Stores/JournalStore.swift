import Foundation
import Observation
import SwiftData
import KopilkaCore

/// Журнал операций: импорт выписки, чтение записей и правки пользователя.
/// Каждый метод делает одно действие и сохраняет базу; цепочки шагов собирает экран.
@Observable
final class JournalStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Импорт

    /// Разбор PDF без записи в базу: начальной настройке нужна шапка (остаток, дата формирования).
    func readStatement(pdfData: Data) throws -> ParsedStatement {
        let lines = try readTextLines(pdfData: pdfData)
        return try KopilkaCore.readStatement(lines: lines)
    }

    func importStatement(_ statement: ParsedStatement, mode: ImportMode) throws -> ImportResult {
        // При ошибке импорт откатывает контекст целиком, и несохранённые правки пропали бы вместе с ним.
        try context.save()
        return try KopilkaCore.importStatement(statement, mode: mode, context: context, now: Date())
    }

    // MARK: - Чтение

    /// Записи периода, новые сверху.
    func loadEntries(in period: Period) throws -> [JournalEntry] {
        let entries = try loadVisibleEntries()
        return entries
            .filter { entry in period.contains(entry.day) }
            .sorted { first, second in isShownEarlier(first, than: second) }
    }

    /// «Проверьте новое»: всё, что пользователь ещё не подтвердил.
    func loadUnreviewed() throws -> [JournalEntry] {
        let entries = try loadVisibleEntries()
        return entries
            .filter { entry in !entry.isReviewed }
            .sorted { first, second in isShownEarlier(first, than: second) }
    }

    // MARK: - Правки пользователя

    func updateEntry(_ entry: JournalEntry, title: String, categoryId: String?) throws {
        entry.title = title
        entry.categoryId = categoryId
        try context.save()
    }

    /// Правило пользователя для продавца: следующие операции у него получат ту же категорию и название.
    /// У переводов продавца нет (пустой ключ) — правило не создаём, возвращаем nil.
    func saveMerchantRule(merchantKey: String, categoryId: String, title: String?) throws -> MerchantRule? {
        guard !merchantKey.isEmpty else { return nil }

        let existingRule = try findMerchantRule(merchantKey: merchantKey)
        let rule = existingRule ?? insertMerchantRule(merchantKey: merchantKey, categoryId: categoryId)
        rule.categoryId = categoryId
        rule.title = title
        // Правка встроенного правила с тем же ключом становится правилом пользователя: засев его не перезапишет.
        rule.isBuiltIn = false
        try context.save()
        return rule
    }

    /// Непроверенные записи того же продавца получают категорию и название из правила.
    func applyRuleToUnreviewed(_ rule: MerchantRule) throws {
        let entries = try loadUnreviewed()
        let sameMerchantEntries = entries.filter { entry in entry.merchantKey == rule.merchantKey }
        for entry in sameMerchantEntries {
            entry.categoryId = rule.categoryId
            if let title = rule.title {
                entry.title = title
            }
        }
        try context.save()
    }

    /// «Всё ок → в журнал».
    func markAllReviewed() throws {
        let entries = try loadUnreviewed()
        for entry in entries {
            entry.isReviewed = true
        }
        try context.save()
    }

    /// «Это та же операция»: `remove` скрывается, его источники переезжают в `keep`.
    func mergeEntries(keep: JournalEntry, remove: JournalEntry) throws {
        KopilkaCore.mergeEntries(keep: keep, remove: remove)
        try context.save()
    }

    // MARK: - Внутреннее

    /// Склеенные записи (`mergedInto`) остаются в базе только ради ключей источников — пользователю их не показываем.
    private func loadVisibleEntries() throws -> [JournalEntry] {
        let entries = try context.fetch(FetchDescriptor<JournalEntry>())
        return entries.filter { entry in entry.mergedInto == nil }
    }

    private func findMerchantRule(merchantKey: String) throws -> MerchantRule? {
        let descriptor = FetchDescriptor<MerchantRule>(predicate: #Predicate { rule in rule.merchantKey == merchantKey })
        return try context.fetch(descriptor).first
    }

    private func insertMerchantRule(merchantKey: String, categoryId: String) -> MerchantRule {
        let rule = MerchantRule(merchantKey: merchantKey, categoryId: categoryId)
        context.insert(rule)
        return rule
    }
}

/// Новые дни сверху; внутри дня — в порядке добавления, сначала последние.
private func isShownEarlier(_ first: JournalEntry, than second: JournalEntry) -> Bool {
    guard first.day == second.day else { return first.day > second.day }
    return first.createdAt > second.createdAt
}
