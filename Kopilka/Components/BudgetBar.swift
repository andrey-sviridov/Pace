import SwiftUI
import KopilkaCore

/// Часть полосы бюджета: подпись в легенде, сумма и цвет.
struct BudgetBarSegment: Identifiable {
    let title: String
    let amount: Decimal
    let color: Color
    /// Превышение (перерасход, «распределено больше дохода»): уже входит в остальные части,
    /// поэтому рисуется поверх правого края полосы, а сумма в легенде — статусным цветом.
    var isOverAmount = false
    /// Метка в легенде кружком-контуром: заливка цвета дорожки на светлом фоне карточки не видна.
    var hasOutlinedMarker = false

    var id: String { title }
}

/// Полоса «на что уходит доход» с легендой в тысячах. Пустые части не показываются ни в полосе, ни в легенде.
/// Главная собирает части из BudgetSummary, экран лимитов — свои («Не распределено»).
struct BudgetBar: View {
    let segments: [BudgetBarSegment]
    let theme: Theme

    var body: some View {
        let visibleSegments = segments.filter { segment in segment.amount > 0 }
        VStack(alignment: .leading, spacing: 12) {
            BudgetBarStrip(segments: visibleSegments, theme: theme)
            BudgetBarLegend(segments: visibleSegments, theme: theme)
        }
    }
}

extension BudgetBar {
    /// Главная: обязательные · отложено · потрачено · свободно; при перерасходе вместо «Свободно» — «Перерасход».
    init(summary: BudgetSummary, theme: Theme) {
        let isOverspent = summary.freeToSpend < 0
        let freeSegment = isOverspent
            ? BudgetBarSegment(title: "Перерасход", amount: -summary.freeToSpend, color: theme.over, isOverAmount: true)
            : BudgetBarSegment(title: "Свободно", amount: summary.freeToSpend, color: theme.track, hasOutlinedMarker: true)
        let segments = [
            BudgetBarSegment(title: "Обязательные", amount: summary.obligatoryTotal, color: theme.secondaryText.opacity(0.55)),
            BudgetBarSegment(title: "Отложено", amount: summary.savingsGoal, color: theme.accent.opacity(0.45)),
            BudgetBarSegment(title: "Потрачено", amount: summary.flexibleSpent, color: theme.accent),
            freeSegment,
        ]
        self.init(segments: segments, theme: theme)
    }
}

/// Ширина полосы — сумма обычных частей: без перерасхода это доход, с перерасходом — всё использованное
/// (оно больше дохода). Превышение уже сидит внутри обычных частей, поэтому в сумму не добавляется,
/// а закрашивает правый край: левее него — то, что покрыл доход.
private struct BudgetBarStrip: View {
    let segments: [BudgetBarSegment]
    let theme: Theme

    var body: some View {
        let regularSegments = segments.filter { segment in !segment.isOverAmount }
        let overSegments = segments.filter { segment in segment.isOverAmount }
        let total = regularSegments.reduce(Decimal(0)) { sum, segment in sum + segment.amount }

        GeometryReader { geometry in
            // Между частями — зазор в 2 pt, поэтому ширину делим за вычетом зазоров.
            let gapsWidth = CGFloat(max(regularSegments.count - 1, 0)) * 2
            let availableWidth = max(geometry.size.width - gapsWidth, 0)
            ZStack(alignment: .trailing) {
                HStack(spacing: 2) {
                    ForEach(regularSegments) { segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: availableWidth * makeShare(segment.amount, of: total))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(overSegments) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: geometry.size.width * makeShare(segment.amount, of: total))
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
                    LegendMarker(segment: segment, theme: theme)
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

private struct LegendMarker: View {
    let segment: BudgetBarSegment
    let theme: Theme

    var body: some View {
        if segment.hasOutlinedMarker {
            Circle()
                .strokeBorder(theme.secondaryText, lineWidth: 1.5)
                .frame(width: 8, height: 8)
        } else {
            Circle()
                .fill(segment.color)
                .frame(width: 8, height: 8)
        }
    }
}

/// Доля части в полосе; пустая полоса — без частей.
private func makeShare(_ amount: Decimal, of total: Decimal) -> CGFloat {
    guard total > 0 else { return 0 }
    return CGFloat(NSDecimalNumber(decimal: amount / total).doubleValue)
}
