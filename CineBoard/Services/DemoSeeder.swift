import Foundation
import SwiftData

/// Явно демонстрационные профили, чтобы можно было проверить просмотр чужих профилей.
/// У них нет пароля — войти под ними нельзя.
@MainActor
enum DemoSeeder {
    private struct Seed { let id: Int; let title: String; let year: String }
    private struct Demo { let title: String; let details: String; let isPublic: Bool; let films: [Seed] }

    static func seedIfNeeded(_ context: ModelContext) {
        let count =
            (try? context.fetchCount(FetchDescriptor<UserAccount>(predicate: #Predicate { $0.isDemo == true }))) ?? 0
        guard count == 0 else {
            seedSocialIfNeeded(context)
            return
        }

        func make(_ username: String, bio: String, _ collections: [Demo]) {
            let user = UserAccount(username: username, bio: bio, isDemo: true)
            context.insert(user)
            for d in collections {
                let c = MovieCollection(title: d.title, details: d.details, isPublic: d.isPublic)
                context.insert(c)
                c.owner = user
                for f in d.films {
                    let item = CollectionItem(
                        movie: Movie(
                            id: f.id, title: f.title, overview: nil, posterPath: nil,
                            backdropPath: nil, releaseDate: f.year, voteAverage: nil,
                            runtime: nil, genres: nil))
                    context.insert(item)
                    item.collection = c
                }
            }
        }

        make(
            "anna_films", bio: "Demo profile. Loves neon, rain and slow cinema.",
            [
                Demo(
                    title: "Neon and Rain", details: "Cyberpunk and urban melancholy.", isPublic: true,
                    films: [
                        Seed(id: 335984, title: "Blade Runner 2049", year: "2017"),
                        Seed(id: 64690, title: "Drive", year: "2011"),
                        Seed(id: 152601, title: "Her", year: "2013"),
                    ]),
                Demo(
                    title: "Secret List", details: "A demo user's private collection.", isPublic: false,
                    films: [
                        Seed(id: 496243, title: "Parasite", year: "2019")
                    ]),
            ])
        make(
            "max_cinema", bio: "Demo profile. Builds collections for movie nights with friends.",
            [
                Demo(
                    title: "Smart Cinema", details: "Films worth arguing about.", isPublic: true,
                    films: [
                        Seed(id: 329865, title: "Arrival", year: "2016"),
                        Seed(id: 244786, title: "Whiplash", year: "2014"),
                        Seed(id: 496243, title: "Parasite", year: "2019"),
                    ]),
                Demo(
                    title: "For a Cozy Evening", details: "Warm and beautiful.", isPublic: true,
                    films: [
                        Seed(id: 129, title: "Spirited Away", year: "2001"),
                        Seed(id: 120467, title: "The Grand Budapest Hotel", year: "2014"),
                        Seed(id: 194, title: "Amélie", year: "2001"),
                    ]),
            ])
        try? context.save()
        seedSocialIfNeeded(context)
    }

    // MARK: Любимые и отзывы демо-пользователей

    private struct DemoReview { let movie: Seed; let rating: Int; let text: String; let daysAgo: Int }

    private static let annaReviews: [DemoReview] = [
        DemoReview(
            movie: Seed(id: 335984, title: "Blade Runner 2049", year: "2017"), rating: 9,
            text: "Visually the gold standard. Every frame belongs on a wall, and the silence works better than dialogue.", daysAgo: 12),
        DemoReview(
            movie: Seed(id: 64690, title: "Drive", year: "2011"), rating: 8,
            text: "Few words, maximum mood. The soundtrack is still in my playlist.", daysAgo: 30),
        DemoReview(
            movie: Seed(id: 496243, title: "Parasite", year: "2019"), rating: 10,
            text: "A rare case where the hype is fully justified. Go in knowing nothing about the plot.", daysAgo: 5),
    ]
    private static let maxReviews: [DemoReview] = [
        DemoReview(
            movie: Seed(id: 496243, title: "Parasite", year: "2019"), rating: 9,
            text: "We argued about it for half the evening — the best recommendation there is.", daysAgo: 8),
        DemoReview(
            movie: Seed(id: 329865, title: "Arrival", year: "2016"), rating: 9,
            text: "Sci-fi that tugs at the heart. The ending makes you rewatch everything from the start.", daysAgo: 20),
        DemoReview(
            movie: Seed(id: 120467, title: "The Grand Budapest Hotel", year: "2014"), rating: 8, text: "", daysAgo: 3),
    ]
    private static let annaFavorites: [Seed] = [
        Seed(id: 335984, title: "Blade Runner 2049", year: "2017"),
        Seed(id: 64690, title: "Drive", year: "2011"),
        Seed(id: 152601, title: "Her", year: "2013"),
        Seed(id: 496243, title: "Parasite", year: "2019"),
    ]
    private static let maxFavorites: [Seed] = [
        Seed(id: 329865, title: "Arrival", year: "2016"),
        Seed(id: 244786, title: "Whiplash", year: "2014"),
        Seed(id: 129, title: "Spirited Away", year: "2001"),
    ]

    private static func movie(_ s: Seed) -> Movie {
        Movie(
            id: s.id, title: s.title, overview: nil, posterPath: nil, backdropPath: nil,
            releaseDate: s.year, voteAverage: nil, runtime: nil, genres: nil)
    }

    private static let displayNames = ["anna_films": "Anna Fields", "max_cinema": "Max Cinema"]

    /// Добавляет демо-пользователям имена, любимые фильмы, отзывы и связи (в том числе при обновлении со старой версии).
    static func seedSocialIfNeeded(_ context: ModelContext) {
        let users = (try? context.fetch(FetchDescriptor<UserAccount>(predicate: #Predicate { $0.isDemo == true }))) ?? []
        for user in users where user.displayName.isEmpty {
            if let name = displayNames[user.username] { user.displayName = name }
        }
        seedConnectionsIfNeeded(users: users, context: context)
        for (name, reviews, favorites) in [
            ("anna_films", annaReviews, annaFavorites), ("max_cinema", maxReviews, maxFavorites),
        ] {
            guard let user = users.first(where: { $0.username == name }) else { continue }
            if user.reviews.isEmpty {
                for r in reviews {
                    let review = Review(movie: movie(r.movie), rating: r.rating, text: r.text)
                    review.createdAt = Calendar.current.date(byAdding: .day, value: -r.daysAgo, to: .now) ?? .now
                    review.updatedAt = review.createdAt
                    context.insert(review)
                    review.author = user
                }
            }
            if user.favorites.isEmpty {
                for (index, f) in favorites.enumerated() {
                    let fav = FavoriteMovie(movie: movie(f), position: index)
                    context.insert(fav)
                    fav.user = user
                }
            }
        }
        try? context.save()
    }

    /// Демо-связи: Anna и Max подписаны друг на друга (друзья) и лайкают подборки друг друга.
    private static func seedConnectionsIfNeeded(users: [UserAccount], context: ModelContext) {
        guard let anna = users.first(where: { $0.username == "anna_films" }),
            let max = users.first(where: { $0.username == "max_cinema" })
        else { return }
        let existing = (try? context.fetchCount(FetchDescriptor<Follow>())) ?? 0
        guard existing == 0 else { return }
        context.insert(Follow(followerID: anna.id, followeeID: max.id))
        context.insert(Follow(followerID: max.id, followeeID: anna.id))
        for collection in max.collections where collection.isPublic {
            context.insert(CollectionLike(userID: anna.id, collectionID: collection.id))
        }
        for collection in anna.collections where collection.isPublic {
            context.insert(CollectionLike(userID: max.id, collectionID: collection.id))
        }
        try? context.save()
    }
}
