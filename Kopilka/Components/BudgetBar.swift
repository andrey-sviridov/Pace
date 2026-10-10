import SwiftUI
import KopilkaCore

/// Часть полосы бюджета: подпись в легенде, сумма и цвет.
struct BudgetBarSegment: Identifiable {
    let title: String
    let amount: Decimal
    let color: Color
    /// Сумма в легенде статусным цветом — для перерасхода и «распределено больше дохода».
    var isOverAmount = false

    var id: String { title }
}

/// Полоса «на что уходит доход» с легендой в тысячах. Отрицательные части в полосе не рисуются,
/// но остаются в легенде: перерасход видно по подписи, а не только по цвету (спека §9).
/// Главная собирает части из BudgetSummary, экран лимитов — свои («Не распределено»).
struct BudgetBar: View {
    let segments: [BudgetBarSegment]
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BudgetBarStrip(segments: segments, theme: theme)
            BudgetBarLegend(segments: segments, theme: theme)
        }
    }
}

extension BudgetBar {
    /// Главная: обязательные · отложено · потрачено · свободно; при перерасходе вместо «Свободно» — «Перерасход».
    init(summary: BudgetSummary, theme: Theme) {
        let isOverspent = summary.freeToSpend < 0
        let freeSegment = isOverspent
            ? BudgetBarSegment(title: "Перерасход", amount: -summary.freeToSpend, color: theme.over, isOverAmount: true)
            : BudgetBarSegment(title: "Свободно", amount: summary.freeToSpend, color: theme.track)
        let segments = [
            BudgetBarSegment(title: "Обязательные", amount: summary.obligatoryTotal, color: theme.secondaryText.opacity(0.55)),
            BudgetBarSegment(title: "Отложено", amount: summary.savingsGoal, color: theme.accent.opacity(0.45)),
            BudgetBarSegment(title: "Потрачено", amount: summary.flexibleSpent, color: theme.accent),
            freeSegment,
        ]
        self.init(segments: segments, theme: theme)
    }
}

private struct BudgetBarStrip: View {
    let segments: [BudgetBarSegment]
    let theme: Theme

    var body: some View {
        let visibleSegments = segments.filter { segment in segment.amount > 0 }
        let total = visibleSegments.reduce(Decimal(0)) { sum, segment in sum + segment.amount }

        GeometryReader { geometry in
            // Между частями — зазор в 2 pt, поэтому ширину делим за вычетом зазоров.
            let gapsWidth = CGFloat(max(visibleSegments.count - 1, 0)) * 2
            let availableWidth = max(geometry.size.width - gapsWidth, 0)
            HStack(spacing: 2) {
                ForEach(visibleSegments) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: availableWidth * makeShare(segment.amount, of: total))
                }
            }
        }
        .frame(height: 12)
        .background(theme.track)
        .clipShape(Capsule())
    }
}

private struct BudgetBarLegend: View {
    let segments: [BudgetBarSegment]
    let theme: Theme

    var body: some View {
        let columns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(segments) { segment in
                HStack(spacing: 6) {
                    Circle()
                        .fill(segment.color)
                        .frame(width: 8, height: 8)
                    Text(segment.title)
                        .foregroundStyle(theme.secondaryText)
                    Text(formatThousands(segment.amount))
                        .monospacedDigit()
                        .foregroundStyle(segment.isOverAmount ? theme.over : theme.text)
                }
                .font(.footnote)
            }
        }
    }
}

/// Доля части в полосе; пустая полоса — без частей.
private func makeShare(_ amount: Decimal, of total: Decimal) -> CGFloat {
    guard total > 0 else { return 0 }
    return CGFloat(NSDecimalNumber(decimal: amount / total).doubleValue)
}
