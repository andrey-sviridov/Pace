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
    /// Тонкая обводка карточки: в тёмных темах карточка без неё сливается с фоном.
    var cardBorder: Color = .clear
    /// Тема E: заливки «в норме» — градиентом от `accent` к `accentGradientEnd` и со свечением, карточки — стеклом.
    var style: ThemeStyle = .flat
    var accentGradientEnd: Color = .clear

    /// A и C следуют системной светлой/тёмной теме, B, D и E всегда тёмные.
    static func make(_ name: ThemeName, colorScheme: ColorScheme) -> Theme {
        switch name {
        case .light:
            return colorScheme == .dark ? systemDark : systemLight
        case .dark:
            return night
        case .paper:
            return colorScheme == .dark ? paperDark : paperLight
        case .graphite:
            return graphite
        case .glow:
            return glow
        }
    }
}

/// Плоские заливки или со свечением (тема E).
enum ThemeStyle {
    case flat, glow
}

extension Theme {
    var isGlowing: Bool { style == .glow }

    /// Заливка «в норме»: в теме E — градиент, в остальных — цвет акцента.
    var accentFill: AnyShapeStyle {
        guard isGlowing else { return AnyShapeStyle(accent) }
        return AnyShapeStyle(LinearGradient(colors: [accent, accentGradientEnd], startPoint: .leading, endPoint: .trailing))
    }

    /// Блик поверх карточки: в теме E сверху светлее, как у стекла; в остальных его нет.
    var cardSheen: AnyShapeStyle {
        guard isGlowing else { return AnyShapeStyle(Color.clear) }
        return AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.07), .white.opacity(0.01)], startPoint: .top, endPoint: .bottom))
    }

    /// Цвет свечения вокруг заливки; в плоских темах свечения нет.
    func makeGlow(_ color: Color) -> Color {
        isGlowing ? color.opacity(0.55) : .clear
    }
}

// MARK: - Значения из макетов A / B / C

extension Theme {
    /// A, светлая.
    static let systemLight = Theme(
        background: Color(hex: 0xF2F2F7),
        card: Color(hex: 0xFFFFFF),
        text: Color(hex: 0x111111),
        secondaryText: Color(hex: 0x6B6B70),
        track: Color(hex: 0xE5E5EA),
        accent: Color(hex: 0x2A78D6),
        normal: Color(hex: 0x2A78D6),
        warning: Color(hex: 0xEDA100),
        over: Color(hex: 0xE34948),
        income: Color(hex: 0x1E8E4F),
        heroFont: .system(size: 28, weight: .semibold),
        cornerRadius: 14
    )

    /// A, тёмная.
    static let systemDark = Theme(
        background: Color(hex: 0x000000),
        card: Color(hex: 0x1C1C1E),
        text: Color(hex: 0xFFFFFF),
        secondaryText: Color(hex: 0x8E8E93),
        track: Color(hex: 0x2C2C2E),
        accent: Color(hex: 0x3987E5),
        normal: Color(hex: 0x3987E5),
        warning: Color(hex: 0xC98500),
        over: Color(hex: 0xE66767),
        income: Color(hex: 0x30C06A),
        heroFont: .system(size: 28, weight: .semibold),
        cornerRadius: 14
    )

    /// B, всегда тёмная.
    static let night = Theme(
        background: Color(hex: 0x0E0F12),
        card: Color(hex: 0x1A1C21),
        text: Color(hex: 0xF2F2F2),
        secondaryText: Color(hex: 0x8D9099),
        track: Color(hex: 0x2A2D34),
        accent: Color(hex: 0x1BAF7A),
        normal: Color(hex: 0x1BAF7A),
        warning: Color(hex: 0xEDA100),
        over: Color(hex: 0xE66767),
        income: Color(hex: 0x1BAF7A),
        heroFont: .system(size: 28, weight: .semibold),
        cornerRadius: 16
    )

    /// C, светлая «бумага».
    static let paperLight = Theme(
        background: Color(hex: 0xF6F1E8),
        card: Color(hex: 0xFFFCF6),
        text: Color(hex: 0x2B2620),
        secondaryText: Color(hex: 0x857B6E),
        track: Color(hex: 0xE9E1D3),
        accent: Color(hex: 0x3F6B4E),
        normal: Color(hex: 0x3F6B4E),
        warning: Color(hex: 0xB7791F),
        over: Color(hex: 0xB4472F),
        income: Color(hex: 0x3F6B4E),
        heroFont: .system(size: 28, weight: .regular, design: .serif),
        cornerRadius: 10
    )

    /// C, тёмная «бумага».
    static let paperDark = Theme(
        background: Color(hex: 0x1E1B17),
        card: Color(hex: 0x2A2622),
        text: Color(hex: 0xEFE8DC),
        secondaryText: Color(hex: 0xA39887),
        track: Color(hex: 0x3A342D),
        accent: Color(hex: 0x7FA88A),
        normal: Color(hex: 0x7FA88A),
        warning: Color(hex: 0xD69A3A),
        over: Color(hex: 0xD2694F),
        income: Color(hex: 0x7FA88A),
        heroFont: .system(size: 28, weight: .regular, design: .serif),
        cornerRadius: 10
    )
}

// MARK: - E, свечение

extension Theme {
    /// E, всегда тёмная, по макету со свечением: стеклянные карточки, голубой градиент со свечением, иконки у лимитов.
    static let glow = Theme(
        background: Color(hex: 0x0A0F14),
        card: Color(hex: 0x151B21),
        text: Color(hex: 0xF2F6F8),
        secondaryText: Color(hex: 0x8B98A3),
        track: Color(hex: 0x232A31),
        accent: Color(hex: 0x4FE0FF),
        normal: Color(hex: 0x4FE0FF),
        warning: Color(hex: 0xF5B43C),
        over: Color(hex: 0xFF5A5A),
        income: Color(hex: 0x2FD9A0),
        heroFont: .system(size: 40, weight: .semibold),
        cornerRadius: 22,
        cardBorder: .white.opacity(0.1),
        style: .glow,
        accentGradientEnd: Color(hex: 0x3B6CF6)
    )
}

// MARK: - D, графит

extension Theme {
    /// D, всегда тёмная: графитовые карточки с обводкой, один плоский голубой акцент без градиентов и свечения.
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
    @Entry var theme: Theme = Theme.systemLight
}
