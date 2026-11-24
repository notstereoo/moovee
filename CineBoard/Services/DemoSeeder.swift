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
            "anna_films", bio: "Демо-профиль. Люблю неон, дождь и медленное кино.",
            [
                Demo(
                    title: "Неон и дождь", details: "Киберпанк и городская меланхолия.", isPublic: true,
                    films: [
                        Seed(id: 335984, title: "Бегущий по лезвию 2049", year: "2017"),
                        Seed(id: 64690, title: "Драйв", year: "2011"),
                        Seed(id: 152601, title: "Она", year: "2013"),
                    ]),
                Demo(
                    title: "Тайный список", details: "Приватная подборка демо-пользователя.", isPublic: false,
                    films: [
                        Seed(id: 496243, title: "Паразиты", year: "2019")
                    ]),
            ])
        make(
            "max_cinema", bio: "Демо-профиль. Собираю подборки для вечеров с друзьями.",
            [
                Demo(
                    title: "Умное кино", details: "Фильмы, о которых хочется спорить.", isPublic: true,
                    films: [
                        Seed(id: 329865, title: "Прибытие", year: "2016"),
                        Seed(id: 244786, title: "Одержимость", year: "2014"),
                        Seed(id: 496243, title: "Паразиты", year: "2019"),
                    ]),
                Demo(
                    title: "Для уютного вечера", details: "Тёплые и красивые.", isPublic: true,
                    films: [
                        Seed(id: 129, title: "Унесённые призраками", year: "2001"),
                        Seed(id: 120467, title: "Отель «Гранд Будапешт»", year: "2014"),
                        Seed(id: 194, title: "Амели", year: "2001"),
                    ]),
            ])
        try? context.save()
        seedSocialIfNeeded(context)
    }

    // MARK: Любимые и отзывы демо-пользователей

    private struct DemoReview { let movie: Seed; let rating: Int; let text: String; let daysAgo: Int }

    private static let annaReviews: [DemoReview] = [
        DemoReview(
            movie: Seed(id: 335984, title: "Бегущий по лезвию 2049", year: "2017"), rating: 9,
            text: "Визуально — эталон. Каждый кадр можно вешать на стену, а тишина работает лучше диалогов.", daysAgo: 12),
        DemoReview(
            movie: Seed(id: 64690, title: "Драйв", year: "2011"), rating: 8,
            text: "Минимум слов, максимум настроения. Саундтрек до сих пор в плейлисте.", daysAgo: 30),
        DemoReview(
            movie: Seed(id: 496243, title: "Паразиты", year: "2019"), rating: 10,
            text: "Редкий случай, когда хайп полностью оправдан. Лучше идти, ничего о сюжете не зная.", daysAgo: 5),
    ]
    private static let maxReviews: [DemoReview] = [
        DemoReview(
            movie: Seed(id: 496243, title: "Паразиты", year: "2019"), rating: 9,
            text: "Спорили после просмотра полвечера — это лучшая рекомендация.", daysAgo: 8),
        DemoReview(
            movie: Seed(id: 329865, title: "Прибытие", year: "2016"), rating: 9,
            text: "Фантастика, от которой щемит сердце. Финал заставляет пересмотреть всё с начала.", daysAgo: 20),
        DemoReview(
            movie: Seed(id: 120467, title: "Отель «Гранд Будапешт»", year: "2014"), rating: 8, text: "", daysAgo: 3),
    ]
    private static let annaFavorites: [Seed] = [
        Seed(id: 335984, title: "Бегущий по лезвию 2049", year: "2017"),
        Seed(id: 64690, title: "Драйв", year: "2011"),
        Seed(id: 152601, title: "Она", year: "2013"),
        Seed(id: 496243, title: "Паразиты", year: "2019"),
    ]
    private static let maxFavorites: [Seed] = [
        Seed(id: 329865, title: "Прибытие", year: "2016"),
        Seed(id: 244786, title: "Одержимость", year: "2014"),
        Seed(id: 129, title: "Унесённые призраками", year: "2001"),
    ]

    private static func movie(_ s: Seed) -> Movie {
        Movie(
            id: s.id, title: s.title, overview: nil, posterPath: nil, backdropPath: nil,
            releaseDate: s.year, voteAverage: nil, runtime: nil, genres: nil)
    }

    /// Добавляет демо-пользователям любимые фильмы и отзывы (в том числе при обновлении со старой версии).
    static func seedSocialIfNeeded(_ context: ModelContext) {
        let users = (try? context.fetch(FetchDescriptor<UserAccount>(predicate: #Predicate { $0.isDemo == true }))) ?? []
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
}
