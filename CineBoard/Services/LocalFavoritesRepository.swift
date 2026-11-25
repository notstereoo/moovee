import Foundation
import SwiftData

enum FavoritesError: LocalizedError, Equatable {
    case limitReached, saveFailed

    var errorDescription: String? {
        switch self {
        case .limitReached: String(localized: "You can have at most \(FavoritesRules.limit) favorite movies. Remove one to add a new one.")
        case .saveFailed: String(localized: "Could not save changes. Please try again.")
        }
    }
}

@MainActor @Observable
final class LocalFavoritesRepository: FavoritesRepository {
    private(set) var revision = 0
    @ObservationIgnored private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    func favorites(of user: UserAccount) -> [FavoriteMovie] {
        user.favorites.sorted { $0.position < $1.position }
    }

    func isFavorite(movieID: Int, of user: UserAccount) -> Bool {
        user.favorites.contains { $0.movieID == movieID }
    }

    func add(_ movie: Movie, as user: UserAccount) throws {
        guard !isFavorite(movieID: movie.id, of: user) else { return }
        guard user.favorites.count < FavoritesRules.limit else { throw FavoritesError.limitReached }
        let item = FavoriteMovie(movie: movie, position: (user.favorites.map(\.position).max() ?? -1) + 1)
        context.insert(item)
        item.user = user
        try commit()
    }

    func remove(movieID: Int, as user: UserAccount) throws {
        for item in user.favorites where item.movieID == movieID { context.delete(item) }
        try commit()
        try renumber(user)
    }

    func move(from source: IndexSet, to destination: Int, as user: UserAccount) throws {
        let list = reordered(favorites(of: user), from: source, to: destination)
        for (index, item) in list.enumerated() { item.position = index }
        try commit()
    }

    /// Держит позиции плотными (0…n-1) после удаления.
    private func renumber(_ user: UserAccount) throws {
        let list = favorites(of: user)
        guard list.enumerated().contains(where: { $0.offset != $0.element.position }) else { return }
        for (index, item) in list.enumerated() { item.position = index }
        try commit()
    }

    private func commit() throws {
        do {
            try context.save()
            revision += 1
        } catch {
            context.rollback()
            throw FavoritesError.saveFailed
        }
    }
}
