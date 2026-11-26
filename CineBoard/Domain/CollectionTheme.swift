import SwiftUI
import UIKit

/// Цветовая тема карточки подборки: градиент из двух цветов.
/// Задаётся парой «базовых» цветов, а оттенки для светлой и тёмной темы устройства считаются из них:
/// в светлой — яркие и светлые, в тёмной — темнее и спокойнее, чтобы сочетаться и с белым, и с чёрным фоном.
struct CollectionTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let baseTop: UInt32
    let baseBottom: UInt32

    /// Цвета для светлой / тёмной темы устройства.
    var lightTop: UIColor { Self.light(baseTop, bright: 0.97, saturation: 0.5) }
    var lightBottom: UIColor { Self.light(baseBottom, bright: 0.86, saturation: 0.78) }
    var darkTop: UIColor { Self.dark(baseTop, maxBrightness: 0.46) }
    var darkBottom: UIColor { Self.dark(baseBottom, maxBrightness: 0.26) }

    /// Цвета, которые сами подстраиваются под тему устройства.
    var top: Color { Self.adaptive(light: lightTop, dark: darkTop) }
    var bottom: Color { Self.adaptive(light: lightBottom, dark: darkBottom) }

    // MARK: Палитра

    static let all: [CollectionTheme] = [
        // Яркие
        CollectionTheme(id: "ember", name: "Ember", baseTop: 0xF2552C, baseBottom: 0xA8153B),
        CollectionTheme(id: "sunset", name: "Sunset", baseTop: 0xFF8A5B, baseBottom: 0xE8436E),
        CollectionTheme(id: "coral", name: "Coral", baseTop: 0xFF6B6B, baseBottom: 0xC44569),
        CollectionTheme(id: "cherry", name: "Cherry", baseTop: 0xE11D48, baseBottom: 0x7F1D1D),
        CollectionTheme(id: "crimson", name: "Crimson", baseTop: 0xD7263D, baseBottom: 0x5B0E2D),
        CollectionTheme(id: "rose", name: "Rose", baseTop: 0xE8436E, baseBottom: 0x7B2CBF),
        CollectionTheme(id: "magenta", name: "Magenta", baseTop: 0xD946EF, baseBottom: 0x6D28D9),
        CollectionTheme(id: "plum", name: "Plum", baseTop: 0xA93E9B, baseBottom: 0x3D1F6E),
        CollectionTheme(id: "violet", name: "Violet", baseTop: 0x8E54E9, baseBottom: 0x4776E6),
        CollectionTheme(id: "indigo", name: "Indigo", baseTop: 0x6366F1, baseBottom: 0x312E81),
        CollectionTheme(id: "ocean", name: "Ocean", baseTop: 0x1E88E5, baseBottom: 0x0B3C8C),
        CollectionTheme(id: "sky", name: "Sky", baseTop: 0x4FB5E8, baseBottom: 0x6C63D9),
        CollectionTheme(id: "lagoon", name: "Lagoon", baseTop: 0x22D3EE, baseBottom: 0x2563EB),
        CollectionTheme(id: "teal", name: "Teal", baseTop: 0x19A7B8, baseBottom: 0x1B5E8C),
        CollectionTheme(id: "mint", name: "Mint", baseTop: 0x2DD4BF, baseBottom: 0x0F766E),
        CollectionTheme(id: "forest", name: "Forest", baseTop: 0x0F9B6C, baseBottom: 0x0B4F4A),
        CollectionTheme(id: "lime", name: "Lime", baseTop: 0x84CC16, baseBottom: 0x15803D),
        CollectionTheme(id: "amber", name: "Amber", baseTop: 0xFBBF24, baseBottom: 0xEA580C),
        CollectionTheme(id: "gold", name: "Gold", baseTop: 0xF2A33A, baseBottom: 0xB5532A),
        CollectionTheme(id: "peach", name: "Peach", baseTop: 0xFB923C, baseBottom: 0xBE185D),
        // Спокойные
        CollectionTheme(id: "lavender", name: "Lavender", baseTop: 0x9A8FBF, baseBottom: 0x3B3566),
        CollectionTheme(id: "dustyrose", name: "Dusty rose", baseTop: 0xB07A8A, baseBottom: 0x4A2C3A),
        CollectionTheme(id: "clay", name: "Clay", baseTop: 0xB08968, baseBottom: 0x5C4033),
        CollectionTheme(id: "sage", name: "Sage", baseTop: 0x6B8F71, baseBottom: 0x2F4F4F),
        CollectionTheme(id: "moss", name: "Moss", baseTop: 0x6B7F3A, baseBottom: 0x2B3A1D),
        CollectionTheme(id: "fog", name: "Fog", baseTop: 0x94A3B8, baseBottom: 0x334155),
        CollectionTheme(id: "midnight", name: "Midnight", baseTop: 0x3B4B7A, baseBottom: 0x0F172A),
        CollectionTheme(id: "ink", name: "Ink", baseTop: 0x334155, baseBottom: 0x020617),
        CollectionTheme(id: "stone", name: "Stone", baseTop: 0x78716C, baseBottom: 0x292524),
        CollectionTheme(id: "ash", name: "Ash", baseTop: 0x8E8E93, baseBottom: 0x2C2C2E),
        CollectionTheme(id: "slate", name: "Slate", baseTop: 0x5C6B84, baseBottom: 0x232B3E),
        CollectionTheme(id: "graphite", name: "Graphite", baseTop: 0x3A3A3C, baseBottom: 0x111114),
    ]

    static func theme(withID id: String) -> CollectionTheme? { all.first { $0.id == id } }

    // MARK: Свои цвета

    static let customPrefix = "custom:"

    /// Своя тема из двух цветов: код `custom:RRGGBB-RRGGBB`.
    static func custom(top: UInt32, bottom: UInt32) -> CollectionTheme {
        CollectionTheme(id: customCode(top: top, bottom: bottom), name: "Custom", baseTop: top, baseBottom: bottom)
    }

    static func customCode(top: UInt32, bottom: UInt32) -> String {
        String(format: "%@%06X-%06X", customPrefix, top & 0xFFFFFF, bottom & 0xFFFFFF)
    }

    /// Разбирает `custom:RRGGBB-RRGGBB` (и просто `RRGGBB-RRGGBB`).
    static func parseCustom(_ code: String) -> (top: UInt32, bottom: UInt32)? {
        let body = code.hasPrefix(customPrefix) ? String(code.dropFirst(customPrefix.count)) : code
        let parts = body.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.count == 6 }),
            let top = UInt32(parts[0], radix: 16), let bottom = UInt32(parts[1], radix: 16)
        else { return nil }
        return (top, bottom)
    }

    static func isCustom(_ id: String) -> Bool { id.hasPrefix(customPrefix) }

    /// Выбранная тема подборки (готовая или своя), а если не выбрана — стабильный цвет по названию.
    static func resolve(for collection: MovieCollection) -> CollectionTheme {
        if let colors = parseCustom(collection.themeID), isCustom(collection.themeID) {
            return custom(top: colors.top, bottom: colors.bottom)
        }
        if let chosen = theme(withID: collection.themeID) { return chosen }
        let seed = collection.title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 9973 }
        return all[abs(seed) % all.count]
    }

    // MARK: Расчёт оттенков

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    private static func hsb(_ hex: UInt32) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(hex: hex).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (h, s, b)
    }

    /// Светлая тема: цвет остаётся тем же по тону, но светлый и яркий.
    static func light(_ hex: UInt32, bright: CGFloat, saturation: CGFloat) -> UIColor {
        let c = hsb(hex)
        return UIColor(hue: c.h, saturation: min(1, c.s * saturation + 0.02), brightness: bright, alpha: 1)
    }

    /// Тёмная тема: глубже и спокойнее; уже тёмные цвета почти не меняются.
    static func dark(_ hex: UInt32, maxBrightness: CGFloat) -> UIColor {
        let c = hsb(hex)
        return UIColor(hue: c.h, saturation: c.s * 0.85, brightness: min(c.b, maxBrightness), alpha: 1)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// Цвет в виде 0xRRGGBB (sRGB).
    var rgbHex: UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ x: CGFloat) -> UInt32 { UInt32((min(max(x, 0), 1) * 255).rounded()) }
        return (byte(r) << 16) | (byte(g) << 8) | byte(b)
    }
}

extension Color {
    init(hex: UInt32) { self.init(UIColor(hex: hex)) }
}
