import SwiftUI

/// Временный экран для вкладок, которые ещё не сделаны.
struct PlaceholderScreen: View {
    let title: String
    let text: String

    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                Card {
                    Text(text)
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .background(theme.background)
            .navigationTitle(title)
        }
    }
}
