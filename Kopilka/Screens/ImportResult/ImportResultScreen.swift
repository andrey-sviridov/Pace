import SwiftUI
import KopilkaCore

/// Итог импорта выписки: сколько добавлено, склеено, уже было и сколько ждёт проверки.
struct ImportResultScreen: View {
    let result: ImportResult
    let onReview: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(theme.accent)
            Text("Выписка загружена")
                .font(theme.heroFont)
                .foregroundStyle(theme.text)
            Text(makeAccountTitle(result.accountKind))
                .foregroundStyle(theme.secondaryText)
            Card {
                Text(makeSummaryLine(result))
                    .font(.headline)
                    .foregroundStyle(theme.text)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            Spacer()
            Button(action: onReview) {
                Text("Проверить")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
        }
        .padding()
        .background(theme.background)
    }
}

/// «Добавлено N · склеено K · уже было M · на проверку R».
/// Внутри части пробелы неразрывные, чтобы число не уезжало на другую строку от своей подписи.
private func makeSummaryLine(_ result: ImportResult) -> String {
    let parts = [
        "Добавлено\u{00A0}\(result.addedCount)",
        "склеено\u{00A0}\(result.attachedCount)",
        "уже\u{00A0}было\u{00A0}\(result.alreadyKnownCount)",
        "на\u{00A0}проверку\u{00A0}\(result.needsReviewCount)",
    ]
    return parts.joined(separator: " · ")
}

private func makeAccountTitle(_ kind: AccountKind) -> String {
    switch kind {
    case .card:
        return "Счёт карты"
    case .deposit:
        return "Депозит"
    case .ownOtherCard:
        return "Другая своя карта"
    }
}

