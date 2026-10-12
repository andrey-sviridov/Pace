import SwiftUI

/// Подсветка строки, пока палец на ней, — как у строк списка в iOS.
/// Загорается сразу, а гаснет плавно: при коротком тапе отпускание наступает почти мгновенно,
/// и без затухания подсветку не успевали бы увидеть — экран уже уезжал.
struct PressedRowStyle: ButtonStyle {
    let highlight: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(configuration.isPressed ? highlight : .clear)
                    .animation(configuration.isPressed ? nil : .easeOut(duration: 0.35), value: configuration.isPressed)
            }
    }
}
