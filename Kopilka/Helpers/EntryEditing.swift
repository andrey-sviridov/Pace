import Foundation
import KopilkaCore

/// Правка названия или категории пользователем (спека §5.5): сама запись, правило продавца
/// и непроверенные записи того же продавца. Общая для «Проверьте новое» и карточки записи.
/// `ruleTitle` — какое название запомнить в правиле: новое при правке названия, прежнее из правила при правке категории.
func saveUserEdit(
    _ entry: JournalEntry,
    title: String,
    categoryId: String?,
    ruleTitle: String?,
    journalStore: JournalStore
) throws {
    try journalStore.updateEntry(entry, title: title, categoryId: categoryId)

    // Категория ещё не выбрана (переименовали неизвестную покупку) — правилу нечего запомнить,
    // а подставленная за пользователя категория сделала бы следующие покупки продавца проверенными.
    guard let categoryId else { return }
    guard let rule = try journalStore.saveMerchantRule(merchantKey: entry.merchantKey, categoryId: categoryId, title: ruleTitle) else { return }
    try journalStore.applyRuleToUnreviewed(rule)
}
