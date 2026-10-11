import SwiftUI

/// База не открылась: работать нельзя, но и падать молча нельзя — показываем причину.
struct StartupErrorScreen: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Не удалось открыть данные", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        }
    }
}
