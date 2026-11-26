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

    /// Подборки, показанные прямо в профиле: закреплённые автором или самые новые (не больше трёх).
    var featuredCollections: [MovieCollection] {
        _ = collectionRepository.revision
        return user.featuredCollections(visibleTo: session.currentUser)
    }

    var hasMoreCollections: Bool { collections.count > featuredCollections.count }

    var favorites: [FavoriteMovie] {
        _ = favoritesRepository.revision
        return isContentHidden ? [] : favoritesRepository.favorites(of: user)
    }

    var reviews: [Review] {
        _ = reviewRepository.revision
        return isContentHidden ? [] : reviewRepository.reviews(by: user)
    }

    /// Последние отзывы для профиля; остальные — на экране «все».
    var featuredReviews: [Review] { Array(reviews.prefix(CollectionRules.profileLimit)) }
    var hasMoreReviews: Bool { reviews.count > CollectionRules.profileLimit }

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

    func likeCount(of collection: MovieCollection) -> Int {
        _ = social.revision
        return social.likeCount(of: collection)
    }

    func saveCount(of collection: MovieCollection) -> Int {
        _ = social.revision
        return social.saveCount(of: collection)
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

    // MARK: Сохранение чужих подборок

    /// Свои подборки сохранять не нужно — они уже в профиле.
    func canSave(_ c: MovieCollection) -> Bool {
        guard let me = session.currentUser else { return false }
        return c.owner?.id != me.id
    }

    func isSaved(_ c: MovieCollection) -> Bool {
        _ = social.revision
        guard let me = session.currentUser else { return false }
        return social.isSaved(c, by: me)
    }

    func toggleSave(_ c: MovieCollection) {
        guard let me = session.currentUser else { return }
        do { try social.setSaved(!social.isSaved(c, by: me), c, as: me) } catch {
            errorMessage = userMessage(for: error)
        }
    }

    // MARK: Закрепление подборок (только свои)

    /// Закреплённые, по порядку.
    var pinnedCollections: [MovieCollection] {
        _ = collectionRepository.revision
        return collections.filter { $0.pinPosition >= 0 }.sorted { $0.pinPosition < $1.pinPosition }
    }

    var unpinnedCollections: [MovieCollection] {
        _ = collectionRepository.revision
        return collections.filter { $0.pinPosition < 0 }
    }

    func pin(_ c: MovieCollection) { perform { try collectionRepository.pin(c, as: $0) } }
    func unpin(_ c: MovieCollection) { perform { try collectionRepository.unpin(c, as: $0) } }

    func movePinned(from source: IndexSet, to destination: Int) {
        perform { try collectionRepository.movePinned(from: source, to: destination, as: $0) }
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
