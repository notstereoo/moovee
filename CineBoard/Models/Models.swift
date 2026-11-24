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

struct MoviePage: Decodable, Sendable {
    let page: Int
    let results: [Movie]
    let totalPages: Int
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
    ]

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(models), configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
    }
}

@Model
final class UserAccount {
    @Attribute(.unique) var id: UUID
    /// Всегда в нижнем регистре.
    @Attribute(.unique) var username: String
    var bio: String
    var passwordHash: Data?
    var salt: Data?
    /// Демо-профили не имеют пароля и не позволяют войти.
    var isDemo: Bool
    var createdAt: Date

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

    /// Коллекции этого пользователя, которые разрешено видеть `viewer`:
    /// владельцу — все, остальным — только публичные.
    func collections(visibleTo viewer: UserAccount?) -> [MovieCollection] {
        collections.filter { $0.isVisible(to: viewer) }.sorted { $0.createdAt > $1.createdAt }
    }
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

    func isVisible(to viewer: UserAccount?) -> Bool {
        if isPublic { return true }
        guard let viewer, let owner else { return false }
        return owner.id == viewer.id
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
