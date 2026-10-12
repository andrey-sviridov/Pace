import SwiftUI
import SwiftData
import PaceCore

/// Продавцы одной категории за период — открывается тапом по полосе «Куда уходят деньги?», тап по продавцу — его операции.
/// Сумма продавцов равна полосе: ядро считает те же части трат.
struct CategoryMerchantsScreen: View {
    let categoryId: String
    let period: Period

    @Environment(\.theme) private var theme

    /// Только записи категории: все записи база отдаёт ~50 мс, и переход на экран заметно дёргался.
    @Query private var entries: [JournalEntry]
    @Query(sort: \SpendingCategory.sortOrder) private var categories: [SpendingCategory]

    init(categoryId: String, period: Period) {
        self.categoryId = categoryId
        self.period = period
        // «Комиссии банка» снимаются с записей любой категории — здесь фильтровать нечем, нужны все.
        guard categoryId != "bankFees" else { return }
        // Траты без категории ядро собирает под id "uncategorized", в базе у них категории нет.
        let storedCategoryId: String? = categoryId == "uncategorized" ? nil : categoryId
        _entries = Query(filter: #Predicate<JournalEntry> { entry in entry.categoryId == storedCategoryId })
    }

    var body: some View {
        let merchants = calculateMerchantSpending(categoryId: categoryId, period: period, entries: entries, categories: categories)
        let total = merchants.reduce(Decimal(0)) { sum, merchant in sum + merchant.total }
        // Траты без категории ядро собирает под id "uncategorized" — называем их, как журнал.
        let title = makeCategoryName(categoryId: categoryId == "uncategorized" ? nil : categoryId, namesById: makeCategoryNamesById(categories))

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(formatShortDay(period.start)) – \(formatShortDay(period.endExclusive.adding(days: -1)))")
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText)
                    MoneyText(amount: total, style: .hero)
                }
                .padding(.horizontal, 4)
                Card {
                    if merchants.isEmpty {
                        Text("В этом периоде трат нет")
                            .foregroundStyle(theme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(merchants, id: \.title) { merchant in
                                NavigationLink(value: AnalyticsDestination.merchantOperations(title: merchant.title, categoryId: categoryId, period: period)) {
                                    MerchantRow(merchant: merchant, theme: theme)
                                }
                                .buttonStyle(PressedRowStyle(highlight: theme.track))
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MerchantRow: View {
    let merchant: MerchantSpending
    let theme: Theme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(merchant.title)
                    .foregroundStyle(theme.text)
                Text(formatOperationCount(merchant.operationCount))
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
            MoneyText(amount: merchant.total)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Показать операции")
    }
}
