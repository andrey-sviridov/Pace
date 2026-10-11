import SwiftUI

/// Карточка на фоне экрана: цвет и скругление из темы.
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.theme) private var theme

    var body: some View {
        content
            .padding()
            .background(theme.card, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius).strokeBorder(theme.cardBorder, lineWidth: 1))
    }
}
