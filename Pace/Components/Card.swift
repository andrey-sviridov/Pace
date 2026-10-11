import SwiftUI

/// Карточка на фоне экрана: цвет и скругление из темы.
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.theme) private var theme

    var body: some View {
        content
            .padding()
            .background {
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .fill(theme.card)
                    .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius).fill(theme.cardSheen))
            }
            .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius).strokeBorder(theme.cardBorder, lineWidth: 1))
    }
}
