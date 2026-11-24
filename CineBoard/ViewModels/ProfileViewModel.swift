import Foundation

@MainActor @Observable
final class ProfileViewModel {
    let user: UserAccount
    var errorMessage: String?
    private let collectionRepository: any CollectionRepository
    private let reviewRepository: any ReviewRepository
    private let favoritesRepository: any FavoritesRepository
    private let session: AppSession

    init(
        user: UserAccount, collections: any CollectionRepository, reviews: any ReviewRepository,
        favorites: any FavoritesRepository, session: AppSession
    ) {
        self.user = user
        self.collectionRepository = collections
        self.reviewRepository = reviews
        self.favoritesRepository = favorites
        self.session = session
    }

    var isMe: Bool { session.currentUser?.id == user.id }
    var isAvailable: Bool { user.modelContext != nil }
    /// Закрытый профиль чужого пользователя: показываем только имя.
    var isContentHidden: Bool { !user.isContentVisible(to: session.currentUser) }

    /// Для чужого профиля — только публичные подборки; для своего — все.
    var collections: [MovieCollection] {
        _ = collectionRepository.revision
        return user.collections(visibleTo: session.currentUser)
    }

    var favorites: [FavoriteMovie] {
        _ = favoritesRepository.revision
        return isContentHidden ? [] : favoritesRepository.favorites(of: user)
    }

    var reviews: [Review] {
        _ = reviewRepository.revision
        return isContentHidden ? [] : reviewRepository.reviews(by: user)
    }

    func removeFavorite(movieID: Int) {
        perform { try favoritesRepository.remove(movieID: movieID, as: $0) }
    }

    func moveFavorites(from source: IndexSet, to destination: Int) {
        perform { try favoritesRepository.move(from: source, to: destination, as: $0) }
    }

    private func perform(_ op: (UserAccount) throws -> Void) {
        guard isMe, let me = session.currentUser else { return }
        do { try op(me) } catch { errorMessage = userMessage(for: error) }
    }
}
