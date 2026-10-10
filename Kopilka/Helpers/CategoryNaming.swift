import Foundation
import KopilkaCore

/// Название категории по id для строк списков: словарь строится один раз на экран, а не в каждой строке.
func makeCategoryNamesById(_ categories: [SpendingCategory]) -> [String: String] {
    Dictionary(categories.map { category in (category.id, category.name) }, uniquingKeysWith: { first, second in first })
}

/// Категории нет — классификатор продавца не узнал.
func makeCategoryName(categoryId: String?, namesById: [String: String]) -> String {
    guard let categoryId else { return "Не определено" }
    return namesById[categoryId] ?? categoryId
}
