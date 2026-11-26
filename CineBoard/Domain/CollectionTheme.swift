import SwiftUI

/// Цветовая тема карточки подборки: градиент из двух цветов, подобранных так, чтобы белый текст читался.
struct CollectionTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let top: Color
    let bottom: Color

    static let all: [CollectionTheme] = [
        CollectionTheme(id: "ember", name: "Ember", top: Color(hex: 0xF2552C), bottom: Color(hex: 0xA8153B)),
        CollectionTheme(id: "ocean", name: "Ocean", top: Color(hex: 0x1E88E5), bottom: Color(hex: 0x0B3C8C)),
        CollectionTheme(id: "violet", name: "Violet", top: Color(hex: 0x8E54E9), bottom: Color(hex: 0x4776E6)),
        CollectionTheme(id: "forest", name: "Forest", top: Color(hex: 0x0F9B6C), bottom: Color(hex: 0x0B4F4A)),
        CollectionTheme(id: "rose", name: "Rose", top: Color(hex: 0xE8436E), bottom: Color(hex: 0x7B2CBF)),
        CollectionTheme(id: "gold", name: "Gold", top: Color(hex: 0xF2A33A), bottom: Color(hex: 0xB5532A)),
        CollectionTheme(id: "teal", name: "Lagoon", top: Color(hex: 0x19A7B8), bottom: Color(hex: 0x1B5E8C)),
        CollectionTheme(id: "plum", name: "Plum", top: Color(hex: 0xA93E9B), bottom: Color(hex: 0x3D1F6E)),
        CollectionTheme(id: "crimson", name: "Crimson", top: Color(hex: 0xD7263D), bottom: Color(hex: 0x5B0E2D)),
        CollectionTheme(id: "sky", name: "Sky", top: Color(hex: 0x4FB5E8), bottom: Color(hex: 0x6C63D9)),
        CollectionTheme(id: "slate", name: "Slate", top: Color(hex: 0x5C6B84), bottom: Color(hex: 0x232B3E)),
        CollectionTheme(id: "graphite", name: "Graphite", top: Color(hex: 0x3A3A3C), bottom: Color(hex: 0x111114)),
    ]

    static func theme(withID id: String) -> CollectionTheme? { all.first { $0.id == id } }

    /// Выбранная тема подборки, а если не выбрана — стабильный цвет по названию (одна и та же подборка всегда одного цвета).
    static func resolve(for collection: MovieCollection) -> CollectionTheme {
        if let chosen = theme(withID: collection.themeID) { return chosen }
        let seed = collection.title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 9973 }
        return all[abs(seed) % all.count]
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}
