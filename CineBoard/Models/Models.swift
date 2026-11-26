import Foundation
import SwiftData

// MARK: - Каталог (TMDB)

struct Movie: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let title: String
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let voteAverage: Double?
    let runtime: Int?
    let genres: [Genre]?

    struct Genre: Codable, Hashable, Sendable {
        let id: Int
        let name: String
    }

    /// Год выпуска (первые 4 символа даты), если известен.
    var year: String? {
        guard let d = releaseDate, d.count >= 4 else { return nil }
        return String(d.prefix(4))
    }
}

struct MoviePage: Codable, Sendable {
    let page: Int
    let results: [Movie]
    let totalPages: Int
    /// Страница взята из локального кэша (нет сети), а не из свежего ответа каталога.
    var isFromCache = false

    private enum CodingKeys: String, CodingKey { case page, results, totalPages }
}

extension Movie {
    init(item: CollectionItem) {
        self.init(
            id: item.movieID, title: item.title, overview: nil, posterPath: item.posterPath,
            backdropPath: nil, releaseDate: item.year, voteAverage: item.rating,
            runtime: nil, genres: nil)
    }
}

extension Movie {
    init(review r: Review) {
        self.init(
            id: r.movieID, title: r.movieTitle, overview: nil, posterPath: r.posterPath,
            backdropPath: nil, releaseDate: r.year, voteAverage: nil, runtime: nil, genres: nil)
    }

    init(favorite f: FavoriteMovie) {
        self.init(
            id: f.movieID, title: f.title, overview: nil, posterPath: f.posterPath,
            backdropPath: nil, releaseDate: f.year, voteAverage: nil, runtime: nil, genres: nil)
    }
}

// MARK: - Пользовательские данные (SwiftData)

/// Все модели SwiftData в одном месте — для приложения, превью и тестов.
enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        UserAccount.self, MovieCollection.self, CollectionItem.self, Review.self, FavoriteMovie.self,
        Follow.self, CollectionLike.self, SavedCollection.self,
    ]

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let container = try ModelContainer(
            for: Schema(models), configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
        if !inMemory { StoreProtection.apply(to: container) }
        return container
    }
}

@Model
final class UserAccount {
    @Attribute(.unique) var id: UUID
    /// Всегда в нижнем регистре.
    @Attribute(.unique) var username: String
    var bio: String
    /// Устарело: используется только для переноса старых данных в Keychain, затем остаётся пустым.
    var passwordHash: Data?
    var salt: Data?
    /// Демо-профили не имеют пароля и не позволяют войти.
    var isDemo: Bool
    var createdAt: Date
    /// Закрытый профиль: другие пользователи не видят любимые, подборки и список отзывов.
    var isProfilePrivate: Bool = false
    /// Отображаемое имя (может повторяться у разных людей). Пусто — показываем никнейм.
    var displayName: String = ""
    /// Сохранённые «свои цвета» подборок: коды `RRGGBB-RRGGBB` через запятую (не больше `CollectionRules.savedThemesLimit`).
    var savedThemes: String = ""
    /// Аватар и баннер хранятся уменьшенными JPEG-файлами рядом с базой.
    @Attribute(.externalStorage) var avatarData: Data?
    @Attribute(.externalStorage) var bannerData: Data?

    @Relationship(deleteRule: .cascade, inverse: \MovieCollection.owner)
    var collections: [MovieCollection] = []

    @Relationship(deleteRule: .cascade, inverse: \Review.author)
    var reviews: [Review] = []

    @Relationship(deleteRule: .cascade, inverse: \FavoriteMovie.user)
    var favorites: [FavoriteMovie] = []

    init(username: String, bio: String = "", passwordHash: Data? = nil, salt: Data? = nil, isDemo: Bool = false) {
        self.id = UUID()
        self.username = username
        self.bio = bio
        self.passwordHash = passwordHash
        self.salt = salt
        self.isDemo = isDemo
        self.createdAt = .now
    }

    var savedThemeCodes: [String] {
        savedThemes.split(separator: ",").map(String.init).filter { CollectionTheme.parseCustom($0) != nil }
    }

    /// Имя для показа в интерфейсе: отображаемое имя или, если его нет, никнейм.
    var shownName: String { displayName.isEmpty ? username : displayName }

    /// Видно ли содержимое профиля (любимые, подборки, отзывы) этому зрителю.
    func isContentVisible(to viewer: UserAccount?) -> Bool { !isProfilePrivate || viewer?.id == id }

    /// Подборки, которые показываются прямо в профиле (не больше `CollectionRules.profileLimit`):
    /// закреплённые автором по порядку, а если ничего не закреплено — самые новые.
    func featuredCollections(visibleTo viewer: UserAccount?) -> [MovieCollection] {
        let visible = collections(visibleTo: viewer)
        let pinned = visible.filter { $0.pinPosition >= 0 }.sorted { $0.pinPosition < $1.pinPosition }
        return Array((pinned.isEmpty ? visible : pinned).prefix(CollectionRules.profileLimit))
    }

    /// Коллекции этого пользователя, которые разрешено видеть `viewer`:
    /// владельцу — все, остальным — только публичные (если профиль открыт).
    func collections(visibleTo viewer: UserAccount?) -> [MovieCollection] {
        guard isContentVisible(to: viewer) else { return [] }
        return collections.filter { $0.isVisible(to: viewer) }.sorted { $0.createdAt > $1.createdAt }
    }
}

/// Явная идентичность по стабильному уникальному `id`: `navigationDestination(for:)` требует `Hashable`,
/// а на сборке под устройство компилятор не всегда видит соответствие, которое даёт `@Model`.
extension UserAccount: Hashable {
    static func == (lhs: UserAccount, rhs: UserAccount) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@Model
final class MovieCollection {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var isPublic: Bool
    /// Явно выбранная обложка; если nil — постер первого фильма.
    var coverPosterPath: String?
    var createdAt: Date
    /// Цветовая тема карточки (см. `CollectionTheme`); пусто — цвет подбирается автоматически.
    var themeID: String = ""
    /// Позиция среди закреплённых в профиле (0…2); −1 — не закреплена.
    var pinPosition: Int = -1
    var owner: UserAccount?

    @Relationship(deleteRule: .cascade, inverse: \CollectionItem.collection)
    var items: [CollectionItem] = []

    init(title: String, details: String, isPublic: Bool) {
        self.id = UUID()
        self.title = title
        self.details = details
        self.isPublic = isPublic
        self.createdAt = .now
    }

    var sortedItems: [CollectionItem] { items.sorted { $0.addedAt > $1.addedAt } }

    var coverPath: String? {
        coverPosterPath ?? sortedItems.first(where: { $0.posterPath != nil })?.posterPath
    }

    /// Владелец видит всё; остальные — только публичные подборки открытых профилей.
    func isVisible(to viewer: UserAccount?) -> Bool {
        guard let owner else { return isPublic }
        if viewer?.id == owner.id { return true }
        return isPublic && !owner.isProfilePrivate
    }
}

/// Снимок фильма внутри коллекции (чтобы список работал без сети).
@Model
final class CollectionItem {
    @Attribute(.unique) var id: UUID
    var movieID: Int
    var title: String
    var year: String?
    var posterPath: String?
    var rating: Double?
    var addedAt: Date
    /// Позиция при ручной сортировке подборки.
    var position: Int = 0
    /// Когда снимок последний раз сверялся с каталогом.
    var refreshedAt: Date?
    var collection: MovieCollection?

    init(movie: Movie) {
        self.id = UUID()
        self.movieID = movie.id
        self.title = movie.title
        self.year = movie.year
        self.posterPath = movie.posterPath
        self.rating = (movie.voteAverage ?? 0) > 0 ? movie.voteAverage : nil
        self.addedAt = .now
    }
}

/// Оценка (1–10) и необязательный текст отзыва. Один отзыв на пару (автор, фильм) — это обеспечивает репозиторий.
@Model
final class Review {
    @Attribute(.unique) var id: UUID
    var movieID: Int
    var movieTitle: String
    var year: String?
    var posterPath: String?
    var rating: Int
    var text: String
    var createdAt: Date
    var updatedAt: Date
    var refreshedAt: Date?
    var author: UserAccount?

    init(movie: Movie, rating: Int, text: String) {
        self.id = UUID()
        self.movieID = movie.id
        self.movieTitle = movie.title
        self.year = movie.year
        self.posterPath = movie.posterPath
        self.rating = rating
        self.text = text
        self.createdAt = .now
        self.updatedAt = .now
    }
}

/// Любимый фильм в профиле; `position` задаёт порядок.
@Model
final class FavoriteMovie {
    @Attribute(.unique) var id: UUID
    var movieID: Int
    var title: String
    var year: String?
    var posterPath: String?
    var position: Int
    var addedAt: Date
    var refreshedAt: Date?
    var user: UserAccount?

    init(movie: Movie, position: Int) {
        self.id = UUID()
        self.movieID = movie.id
        self.title = movie.title
        self.year = movie.year
        self.posterPath = movie.posterPath
        self.position = position
        self.addedAt = .now
    }
}

/// Подписка: `followerID` следит за `followeeID`. Взаимные подписки — «друзья».
/// Связи хранятся по идентификаторам; чистку при удалении аккаунта делает `SocialCleanup`.
@Model
final class Follow {
    @Attribute(.unique) var id: UUID
    var followerID: UUID
    var followeeID: UUID
    var createdAt: Date

    init(followerID: UUID, followeeID: UUID) {
        self.id = UUID()
        self.followerID = followerID
        self.followeeID = followeeID
        self.createdAt = .now
    }
}

/// Лайк чужой подборки.
@Model
final class CollectionLike {
    @Attribute(.unique) var id: UUID
    var userID: UUID
    var collectionID: UUID
    var createdAt: Date

    init(userID: UUID, collectionID: UUID) {
        self.id = UUID()
        self.userID = userID
        self.collectionID = collectionID
        self.createdAt = .now
    }
}

/// Чужая подборка, сохранённая себе в профиль.
@Model
final class SavedCollection {
    @Attribute(.unique) var id: UUID
    var userID: UUID
    var collectionID: UUID
    var savedAt: Date

    init(userID: UUID, collectionID: UUID) {
        self.id = UUID()
        self.userID = userID
        self.collectionID = collectionID
        self.savedAt = .now
    }
}
