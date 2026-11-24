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

// MARK: - Пользовательские данные (SwiftData)

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
