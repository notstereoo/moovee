import Foundation

/// Выбор собственных подборок для фильма.
@MainActor @Observable
final class SaveToCollectionViewModel {
    let movie: Movie
    var errorMessage: String?
    private let repository: any CollectionRepository
    private let session: AppSession

    init(movie: Movie, repository: any CollectionRepository, session: AppSession) {
        self.movie = movie
        self.repository = repository
        self.session = session
    }

    var mine: [MovieCollection] {
        _ = repository.revision
        guard let me = session.currentUser else { return [] }
        return repository.collections(ownedBy: me)
    }

    func contains(_ c: MovieCollection) -> Bool { c.items.contains { $0.movieID == movie.id } }

    func toggle(_ c: MovieCollection) {
        guard let user = session.currentUser else { return }
        do {
            if contains(c) {
                try repository.remove(movieID: movie.id, from: c, as: user)
            } else {
                try repository.add(movie, to: c, as: user)
            }
        } catch { errorMessage = userMessage(for: error) }
    }

    /// Добавляет фильм в только что созданную подборку.
    func addToNew(_ c: MovieCollection) {
        guard let user = session.currentUser else { return }
        do { try repository.add(movie, to: c, as: user) } catch { errorMessage = userMessage(for: error) }
    }
}
