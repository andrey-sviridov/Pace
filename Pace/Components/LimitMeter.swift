import SwiftUI
import PaceCore

/// Строка лимита: название, «ост. 42k» или «+2k» при перерасходе, полоса с заливкой и меткой темпа (спека §5.8).
struct LimitMeter: View {
    let status: LimitStatus
    let theme: Theme

    var body: some View {
        let isOver = status.spent > status.limit
        let levelColor = makeLevelColor(status.level, theme: theme)
        HStack(spacing: 12) {
            if theme.isGlowing {
                LimitIcon(iconName: status.category.iconName, color: levelColor)
            }
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
                    fill: status.level == .normal ? theme.accentFill : AnyShapeStyle(levelColor),
                    glowColor: theme.makeGlow(levelColor),
                    theme: theme
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(makeAccessibilityText(status: status, isOver: isOver))
    }
}

private struct LimitMeterTrack: View {
    let usedShare: Double
    let paceShare: Double
    let fill: AnyShapeStyle
    let glowColor: Color
    let theme: Theme

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.track)
                    .frame(height: 6)
                Capsule()
                    .fill(fill)
                    .frame(width: width * min(max(usedShare, 0), 1), height: 6)
                    .shadow(color: glowColor, radius: 6)
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

/// Тема E: иконка категории на подложке цвета статуса, как на макете.
private struct LimitIcon: View {
    let iconName: String
    let color: Color

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 36, height: 36)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
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
