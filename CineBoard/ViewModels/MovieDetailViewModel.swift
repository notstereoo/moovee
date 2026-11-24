import Foundation

@MainActor @Observable
final class MovieDetailViewModel {
    let movie: Movie
    private(set) var detail: Movie?
    private(set) var isLoading = false
    private(set) var loadError: String?
    var actionError: String?

    private let catalog: any MovieCatalog
    private let reviewRepository: any ReviewRepository
    private let favoritesRepository: any FavoritesRepository
    private let session: AppSession

    init(
        movie: Movie, catalog: any MovieCatalog, reviews: any ReviewRepository,
        favorites: any FavoritesRepository, session: AppSession
    ) {
        self.movie = movie
        self.catalog = catalog
        self.reviewRepository = reviews
        self.favoritesRepository = favorites
        self.session = session
    }

    var shown: Movie { detail ?? movie }

    // MARK: Каталог

    func load() async {
        guard detail == nil else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do { detail = try await catalog.details(id: movie.id) } catch is CancellationError {} catch {
            loadError = userMessage(for: error)
        }
    }

    // MARK: Оценки и отзывы

    /// Рейтинг сообщества CineBoard (не путать с рейтингом TMDB).
    var communityRating: CommunityRating? {
        _ = reviewRepository.revision
        return reviewRepository.communityRating(forMovie: movie.id)
    }

    var myReview: Review? {
        _ = reviewRepository.revision
        guard let me = session.currentUser else { return nil }
        return reviewRepository.review(by: me, movieID: movie.id)
    }

    /// Отзывы других пользователей (свой показывается отдельно).
    var otherReviews: [Review] {
        _ = reviewRepository.revision
        let myID = session.currentUser?.id
        return reviewRepository.reviews(forMovie: movie.id).filter { $0.author?.id != myID }
    }

    // MARK: Любимые

    var isFavorite: Bool {
        _ = favoritesRepository.revision
        guard let me = session.currentUser else { return false }
        return favoritesRepository.isFavorite(movieID: movie.id, of: me)
    }

    func toggleFavorite() {
        guard let me = session.currentUser else { return }
        do {
            if isFavorite {
                try favoritesRepository.remove(movieID: movie.id, as: me)
            } else {
                try favoritesRepository.add(shown, as: me)
            }
        } catch { actionError = userMessage(for: error) }
    }
}
