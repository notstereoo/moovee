import Foundation

/// Способ показа фильмов внутри подборки.
enum CollectionSort: String, CaseIterable, Identifiable {
    case added, title, year, rating, manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .added: String(localized: "Сначала новые")
        case .title: String(localized: "По названию")
        case .year: String(localized: "По году")
        case .rating: String(localized: "По рейтингу")
        case .manual: String(localized: "Порядок автора")
        }
    }

    var systemImage: String {
        switch self {
        case .added: "clock"
        case .title: "textformat"
        case .year: "calendar"
        case .rating: "star"
        case .manual: "hand.draw"
        }
    }
}

extension MovieCollection {
    func items(sortedBy sort: CollectionSort) -> [CollectionItem] {
        switch sort {
        case .added:
            return items.sorted { $0.addedAt > $1.addedAt }
        case .title:
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .year:
            return items.sorted { Self.descending($0.year, $1.year, tie: ($0, $1)) }
        case .rating:
            return items.sorted { Self.descending($0.rating, $1.rating, tie: ($0, $1)) }
        case .manual:
            return items.sorted { ($0.position, $1.addedAt) < ($1.position, $0.addedAt) }
        }
    }

    /// Убывание; значения `nil` — в конце; при равенстве — новые добавленные выше.
    private static func descending<T: Comparable>(
        _ a: T?, _ b: T?, tie: (CollectionItem, CollectionItem)
    ) -> Bool {
        switch (a, b) {
        case let (a?, b?) where a != b: return a > b
        case (_?, nil): return true
        case (nil, _?): return false
        default: return tie.0.addedAt > tie.1.addedAt
        }
    }
}

/// Перемещение элементов списка в духе `onMove` (без зависимости от SwiftUI).
func reordered<T>(_ list: [T], from source: IndexSet, to destination: Int) -> [T] {
    var result = list
    let moving = source.sorted().map { list[$0] }
    let insertAt = destination - source.filter { $0 < destination }.count
    for index in source.sorted(by: >) { result.remove(at: index) }
    result.insert(contentsOf: moving, at: min(max(insertAt, 0), result.count))
    return result
}
