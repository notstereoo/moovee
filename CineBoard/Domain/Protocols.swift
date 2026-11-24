import Foundation

/// Источник аккаунтов. Сейчас — локальный (SwiftData), позже — серверный (Sign in with Apple и т. п.).
@MainActor
protocol AuthProvider {
    func register(username: String, password: String) throws -> UserAccount
    func login(username: String, password: String) throws -> UserAccount
    func user(id: UUID) -> UserAccount?
    func updateBio(_ bio: String, for user: UserAccount) throws
}

/// Хранилище подборок. Каждая изменяющая операция проверяет, что `user` — владелец.
/// `revision` растёт после каждого успешного изменения — по нему ViewModel'и обновляют списки.
@MainActor
protocol CollectionRepository: AnyObject {
    var revision: Int { get }

    func collections(ownedBy user: UserAccount) -> [MovieCollection]
    /// Публичные подборки всех, кроме `user`.
    func publicCollections(excluding user: UserAccount?) -> [MovieCollection]

    func create(title: String, details: String, isPublic: Bool, as user: UserAccount) throws -> MovieCollection
    func update(_ c: MovieCollection, title: String, details: String, isPublic: Bool, as user: UserAccount) throws
    func delete(_ c: MovieCollection, as user: UserAccount) throws
    func add(_ movie: Movie, to c: MovieCollection, as user: UserAccount) throws
    func remove(movieID: Int, from c: MovieCollection, as user: UserAccount) throws
    func setCover(of c: MovieCollection, movieID: Int, as user: UserAccount) throws
    /// Меняет порядок автора («Порядок автора» в подборке).
    func moveItems(in c: MovieCollection, from source: IndexSet, to destination: Int, as user: UserAccount) throws
}

struct CommunityRating: Equatable {
    let average: Double
    let count: Int
}

enum ReviewRules {
    static let ratingRange = 1...10
    static let maxTextLength = 1000
}

enum FavoritesRules {
    static let limit = 10
}

/// Оценки и отзывы. Один отзыв на пару (автор, фильм): повторное сохранение обновляет существующий.
@MainActor
protocol ReviewRepository: AnyObject {
    var revision: Int { get }

    /// Отзывы о фильме, новые сверху.
    func reviews(forMovie id: Int) -> [Review]
    func reviews(by user: UserAccount) -> [Review]
    func review(by user: UserAccount, movieID: Int) -> Review?
    func communityRating(forMovie id: Int) -> CommunityRating?

    func save(movie: Movie, rating: Int, text: String, as user: UserAccount) throws -> Review
    func delete(_ review: Review, as user: UserAccount) throws
}

/// Любимые фильмы пользователя (топ с порядком и лимитом).
@MainActor
protocol FavoritesRepository: AnyObject {
    var revision: Int { get }

    func favorites(of user: UserAccount) -> [FavoriteMovie]
    func isFavorite(movieID: Int, of user: UserAccount) -> Bool

    func add(_ movie: Movie, as user: UserAccount) throws
    func remove(movieID: Int, as user: UserAccount) throws
    func move(from source: IndexSet, to destination: Int, as user: UserAccount) throws
}
