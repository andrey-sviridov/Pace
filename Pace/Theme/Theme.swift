import SwiftUI
import PaceCore

/// Набор токенов оформления (спека §9). Экраны берут цвета только отсюда, через `@Environment(\.theme)`.
struct Theme {
    let background: Color
    let card: Color
    let text: Color
    let secondaryText: Color
    /// Фон полос и шкал, по которому идёт заливка.
    let track: Color
    let accent: Color
    /// Статусы лимита: в норме / скоро кончится / превышен.
    let normal: Color
    let warning: Color
    let over: Color
    /// Доход: «+402k» в календаре журнала.
    let income: Color
    /// Шрифт главной цифры «Можно потратить».
    let heroFont: Font
    let cornerRadius: CGFloat
    /// Тонкая обводка карточки, чтобы она не сливалась с фоном.
    let cardBorder: Color
    /// Заливки «в норме» идут градиентом от `accent` к этому цвету.
    let accentGradientEnd: Color
    /// Насколько заметно свечение вокруг заливок.
    let glowOpacity: Double
    /// Блик сверху карточки, как у стекла; на светлой карточке он не нужен.
    let sheenOpacity: Double

    /// Главная тема одна — «Свечение»; режим выбирает её светлый или тёмный вариант.
    static func make(_ name: ThemeName, colorScheme: ColorScheme) -> Theme {
        switch name {
        case .glow:
            return colorScheme == .dark ? glowDark : glowLight
        }
    }
}

extension Theme {
    /// Заливка «в норме»: градиент акцента.
    var accentFill: AnyShapeStyle {
        AnyShapeStyle(LinearGradient(colors: [accent, accentGradientEnd], startPoint: .leading, endPoint: .trailing))
    }

    var cardSheen: AnyShapeStyle {
        AnyShapeStyle(LinearGradient(colors: [.white.opacity(sheenOpacity), .white.opacity(sheenOpacity / 7)], startPoint: .top, endPoint: .bottom))
    }

    /// Цвет свечения вокруг заливки.
    func makeGlow(_ color: Color) -> Color {
        color.opacity(glowOpacity)
    }
}

// MARK: - Свечение

extension Theme {
    /// Тёмная: стеклянные карточки, голубой градиент с мягким свечением.
    static let glowDark = Theme(
        background: Color(hex: 0x0A0F14),
        card: Color(hex: 0x151B21),
        text: Color(hex: 0xF2F6F8),
        secondaryText: Color(hex: 0x8B98A3),
        track: Color(hex: 0x232A31),
        accent: Color(hex: 0x5CC6E6),
        normal: Color(hex: 0x5CC6E6),
        warning: Color(hex: 0xF5B43C),
        over: Color(hex: 0xFF5A5A),
        income: Color(hex: 0x2FD9A0),
        heroFont: .system(size: 40, weight: .semibold),
        cornerRadius: 22,
        cardBorder: .white.opacity(0.1),
        accentGradientEnd: Color(hex: 0x4A7BDB),
        glowOpacity: 0.3,
        sheenOpacity: 0.07
    )

    /// Светлая: белые карточки на холодном светло-сером, тот же градиент чуть темнее — для контраста на белом.
    static let glowLight = Theme(
        background: Color(hex: 0xF1F4F7),
        card: Color(hex: 0xFFFFFF),
        text: Color(hex: 0x0F171E),
        secondaryText: Color(hex: 0x6A7682),
        track: Color(hex: 0xE4E9EE),
        accent: Color(hex: 0x2DADD8),
        normal: Color(hex: 0x2DADD8),
        warning: Color(hex: 0xDB8C00),
        over: Color(hex: 0xE5484D),
        income: Color(hex: 0x14A876),
        heroFont: .system(size: 40, weight: .semibold),
        cornerRadius: 22,
        cardBorder: .black.opacity(0.06),
        accentGradientEnd: Color(hex: 0x3F6FDB),
        glowOpacity: 0.25,
        sheenOpacity: 0
    )
}

extension EnvironmentValues {
    /// Корень приложения кладёт сюда тему из настроек; значение по умолчанию нужно только превью.
    @Entry var theme: Theme = Theme.glowDark
}
