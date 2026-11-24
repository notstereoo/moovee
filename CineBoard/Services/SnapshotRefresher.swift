import Foundation
import SwiftData

/// Фильмы в подборках, отзывах и любимых хранятся снимками (чтобы работать без сети).
/// Фоновая сверка с каталогом обновляет название, год, постер и рейтинг.
@MainActor
enum SnapshotRefresher {
    nonisolated static let maxAge: TimeInterval = 7 * 24 * 3600
    /// Не больше стольких запросов за один запуск, чтобы не упираться в лимиты каталога.
    nonisolated static let batchSize = 20

    @discardableResult
    static func refreshStale(
        context: ModelContext, catalog: any MovieCatalog, now: Date = .now, batchSize: Int = SnapshotRefresher.batchSize
    ) async -> Int {
        guard catalog.isConfigured else { return 0 }
        let threshold = now.addingTimeInterval(-maxAge)

        let items = fetch(CollectionItem.self, context).filter { isStale($0.refreshedAt, threshold) }
        let reviews = fetch(Review.self, context).filter { isStale($0.refreshedAt, threshold) }
        let favorites = fetch(FavoriteMovie.self, context).filter { isStale($0.refreshedAt, threshold) }

        var ids: [Int] = []
        for id in items.map(\.movieID) + reviews.map(\.movieID) + favorites.map(\.movieID) where !ids.contains(id) {
            ids.append(id)
        }
        var refreshed = 0
        for id in ids.prefix(batchSize) {
            if Task.isCancelled { break }
            guard let movie = try? await catalog.details(id: id) else { continue }
            for item in items where item.movieID == id {
                item.title = movie.title
                item.year = movie.year
                item.posterPath = movie.posterPath
                item.rating = (movie.voteAverage ?? 0) > 0 ? movie.voteAverage : nil
                item.refreshedAt = now
            }
            for review in reviews where review.movieID == id {
                review.movieTitle = movie.title
                review.year = movie.year
                review.posterPath = movie.posterPath
                review.refreshedAt = now
            }
            for fav in favorites where fav.movieID == id {
                fav.title = movie.title
                fav.year = movie.year
                fav.posterPath = movie.posterPath
                fav.refreshedAt = now
            }
            refreshed += 1
        }
        if refreshed > 0 { try? context.save() }
        return refreshed
    }

    private static func isStale(_ date: Date?, _ threshold: Date) -> Bool {
        guard let date else { return true }
        return date < threshold
    }

    private static func fetch<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }
}
