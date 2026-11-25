import Foundation

@MainActor @Observable
final class ProfileViewModel {
    enum Tab: String, CaseIterable, Identifiable {
        case home, saved
        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .home: "Home"
            case .saved: "Saved"
            }
        }
    }

    let user: UserAccount
    var tab: Tab = .home
    var errorMessage: String?
    private let collectionRepository: any CollectionRepository
    private let reviewRepository: any ReviewRepository
    private let favoritesRepository: any FavoritesRepository
    private let social: any SocialRepository
    private let session: AppSession

    init(
        user: UserAccount, collections: any CollectionRepository, reviews: any ReviewRepository,
        favorites: any FavoritesRepository, social: any SocialRepository, session: AppSession
    ) {
        self.user = user
        self.collectionRepository = collections
        self.reviewRepository = reviews
        self.favoritesRepository = favorites
        self.social = social
        self.session = session
    }

    var isMe: Bool { session.currentUser?.id == user.id }
    var isAvailable: Bool { user.modelContext != nil }
    /// Закрытый профиль чужого пользователя: показываем только имя, аватар и баннер.
    var isContentHidden: Bool { !user.isContentVisible(to: session.currentUser) }

    // MARK: Содержимое

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

    /// Сохранённые чужие подборки видит только владелец профиля.
    var savedCollections: [MovieCollection] {
        _ = social.revision
        _ = collectionRepository.revision
        return isMe ? social.savedCollections(of: user) : []
    }

    // MARK: Соцсвязи

    var followersCount: Int {
        _ = social.revision
        return social.followersCount(of: user)
    }

    var followingCount: Int {
        _ = social.revision
        return social.followingCount(of: user)
    }

    /// Лайки всех подборок пользователя.
    var totalLikes: Int {
        _ = social.revision
        _ = collectionRepository.revision
        return social.totalLikes(ofOwner: user)
    }

    var canFollow: Bool { !isMe && session.currentUser != nil }

    var isFollowing: Bool {
        _ = social.revision
        guard let me = session.currentUser, !isMe else { return false }
        return social.isFollowing(me, user)
    }

    /// Взаимная подписка.
    var isFriend: Bool {
        _ = social.revision
        guard let me = session.currentUser, !isMe else { return false }
        return social.areFriends(me, user)
    }

    func toggleFollow() {
        guard let me = session.currentUser, !isMe else { return }
        do {
            if social.isFollowing(me, user) {
                try social.unfollow(user, as: me)
            } else {
                try social.follow(user, as: me)
            }
        } catch { errorMessage = userMessage(for: error) }
    }

    // MARK: Любимые (только свои)

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
