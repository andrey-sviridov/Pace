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
    /// Тонкая обводка карточки: на тёмном фоне карточка без неё сливается с фоном.
    let cardBorder: Color
    /// «Свечение»: заливки «в норме» — градиентом от `accent` к `accentGradientEnd` и со свечением, карточки — стеклом.
    var style: ThemeStyle = .flat
    var accentGradientEnd: Color = .clear

    /// Обе темы всегда тёмные.
    static func make(_ name: ThemeName) -> Theme {
        switch name {
        case .graphite:
            return graphite
        case .glow:
            return glow
        }
    }
}

/// Плоские заливки или со свечением.
enum ThemeStyle {
    case flat, glow
}

extension Theme {
    var isGlowing: Bool { style == .glow }

    /// Заливка «в норме»: в «Свечении» — градиент, в «Графите» — цвет акцента.
    var accentFill: AnyShapeStyle {
        guard isGlowing else { return AnyShapeStyle(accent) }
        return AnyShapeStyle(LinearGradient(colors: [accent, accentGradientEnd], startPoint: .leading, endPoint: .trailing))
    }

    /// Блик поверх карточки: в «Свечении» сверху светлее, как у стекла; в «Графите» его нет.
    var cardSheen: AnyShapeStyle {
        guard isGlowing else { return AnyShapeStyle(Color.clear) }
        return AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.07), .white.opacity(0.01)], startPoint: .top, endPoint: .bottom))
    }

    /// Цвет свечения вокруг заливки; в «Графите» свечения нет.
    func makeGlow(_ color: Color) -> Color {
        isGlowing ? color.opacity(0.3) : .clear
    }
}

// MARK: - Свечение

extension Theme {
    /// По макету со свечением: стеклянные карточки, голубой градиент со свечением, иконки у лимитов.
    static let glow = Theme(
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
        style: .glow,
        accentGradientEnd: Color(hex: 0x4A7BDB)
    )
}

// MARK: - Графит

extension Theme {
    /// Графитовые карточки с обводкой, один плоский голубой акцент без градиентов и свечения.
    static let graphite = Theme(
        background: Color(hex: 0x111317),
        card: Color(hex: 0x1C1F26),
        text: Color(hex: 0xF4F5F7),
        secondaryText: Color(hex: 0x8E8E93),
        track: Color(hex: 0x2A2E37),
        accent: Color(hex: 0x2EB8E6),
        normal: Color(hex: 0x2EB8E6),
        warning: Color(hex: 0xF0A43A),
        over: Color(hex: 0xF0605A),
        income: Color(hex: 0x2FC99A),
        heroFont: .system(size: 34, weight: .bold),
        cornerRadius: 20,
        cardBorder: Color(hex: 0x2A2F3A)
    )
}

extension EnvironmentValues {
    /// Корень приложения кладёт сюда тему из настроек; значение по умолчанию нужно только превью.
    @Entry var theme: Theme = Theme.graphite
}
