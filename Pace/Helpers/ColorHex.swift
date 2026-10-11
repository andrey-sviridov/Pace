import SwiftUI

extension Color {
    /// Цвет из макета в виде 0xRRGGBB: `Color(hex: 0xF2F2F7)`.
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
