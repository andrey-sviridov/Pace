import SwiftUI
import KopilkaCore

/// Строка лимита: название, «ост. 42k» или «+2k» при перерасходе, полоса с заливкой и меткой темпа (спека §5.8).
struct LimitMeter: View {
    let status: LimitStatus
    let theme: Theme

    var body: some View {
        let isOver = status.spent > status.limit
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(status.category.name)
                    .foregroundStyle(theme.text)
                Spacer()
                Text(isOver ? "+\(formatThousands(status.spent - status.limit))" : "ост. \(formatThousands(status.limit - status.spent))")
                    .monospacedDigit()
                    .foregroundStyle(isOver ? theme.over : theme.secondaryText)
            }
            .font(.subheadline)
            LimitMeterTrack(
                usedShare: status.usedShare,
                paceShare: status.paceShare,
                fillColor: makeLevelColor(status.level, theme: theme),
                theme: theme
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(makeAccessibilityText(status: status, isOver: isOver))
    }
}

private struct LimitMeterTrack: View {
    let usedShare: Double
    let paceShare: Double
    let fillColor: Color
    let theme: Theme

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.track)
                    .frame(height: 6)
                Capsule()
                    .fill(fillColor)
                    .frame(width: width * min(max(usedShare, 0), 1), height: 6)
                // Метка темпа: если заливка левее неё, тратим медленнее, чем идут дни.
                Rectangle()
                    .fill(theme.text.opacity(0.7))
                    .frame(width: 2, height: 12)
                    .offset(x: width * min(max(paceShare, 0), 1) - 1)
            }
            .frame(height: 12)
        }
        .frame(height: 12)
    }
}

private func makeLevelColor(_ level: LimitLevel, theme: Theme) -> Color {
    switch level {
    case .normal:
        return theme.normal
    case .warning:
        return theme.warning
    case .over:
        return theme.over
    }
}

private func makeAccessibilityText(status: LimitStatus, isOver: Bool) -> String {
    let amountText = isOver
        ? "превышение \(formatTenge(status.spent - status.limit))"
        : "осталось \(formatTenge(status.limit - status.spent))"
    return "\(status.category.name), \(amountText)"
}
