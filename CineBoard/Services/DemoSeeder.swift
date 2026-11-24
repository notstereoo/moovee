import Foundation
import SwiftData

/// Явно демонстрационные профили, чтобы можно было проверить просмотр чужих профилей.
/// У них нет пароля — войти под ними нельзя.
@MainActor
enum DemoSeeder {
    private struct Seed { let id: Int; let title: String; let year: String }
    private struct Demo { let title: String; let details: String; let isPublic: Bool; let films: [Seed] }

    static func seedIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<UserAccount>(predicate: #Predicate { $0.isDemo == true }))) ?? 0
        guard count == 0 else { return }

        func make(_ username: String, bio: String, _ collections: [Demo]) {
            let user = UserAccount(username: username, bio: bio, isDemo: true)
            context.insert(user)
            for d in collections {
                let c = MovieCollection(title: d.title, details: d.details, isPublic: d.isPublic)
                context.insert(c)
                c.owner = user
                for f in d.films {
                    let item = CollectionItem(movie: Movie(id: f.id, title: f.title, overview: nil, posterPath: nil,
                                                           backdropPath: nil, releaseDate: f.year, voteAverage: nil,
                                                           runtime: nil, genres: nil))
                    context.insert(item)
                    item.collection = c
                }
            }
        }

        make("anna_films", bio: "Демо-профиль. Люблю неон, дождь и медленное кино.", [
            Demo(title: "Неон и дождь", details: "Киберпанк и городская меланхолия.", isPublic: true, films: [
                Seed(id: 335984, title: "Бегущий по лезвию 2049", year: "2017"),
                Seed(id: 64690, title: "Драйв", year: "2011"),
                Seed(id: 152601, title: "Она", year: "2013")]),
            Demo(title: "Тайный список", details: "Приватная подборка демо-пользователя.", isPublic: false, films: [
                Seed(id: 496243, title: "Паразиты", year: "2019")]),
        ])
        make("max_cinema", bio: "Демо-профиль. Собираю подборки для вечеров с друзьями.", [
            Demo(title: "Умное кино", details: "Фильмы, о которых хочется спорить.", isPublic: true, films: [
                Seed(id: 329865, title: "Прибытие", year: "2016"),
                Seed(id: 244786, title: "Одержимость", year: "2014"),
                Seed(id: 496243, title: "Паразиты", year: "2019")]),
            Demo(title: "Для уютного вечера", details: "Тёплые и красивые.", isPublic: true, films: [
                Seed(id: 129, title: "Унесённые призраками", year: "2001"),
                Seed(id: 120467, title: "Отель «Гранд Будапешт»", year: "2014"),
                Seed(id: 194, title: "Амели", year: "2001")]),
        ])
        try? context.save()
    }

    /// Подтягивает постеры демо-фильмов из каталога (если ключ задан).
    static func hydratePosters(context: ModelContext, catalog: any MovieCatalog) async {
        guard catalog.isConfigured else { return }
        let items = ((try? context.fetch(FetchDescriptor<CollectionItem>(predicate: #Predicate { $0.posterPath == nil }))) ?? [])
            .filter { $0.collection?.owner?.isDemo == true }
        guard !items.isEmpty else { return }
        var cache: [Int: Movie] = [:]
        for item in items {
            if cache[item.movieID] == nil { cache[item.movieID] = try? await catalog.details(id: item.movieID) }
            if let m = cache[item.movieID] {
                item.posterPath = m.posterPath
                if let r = m.voteAverage, r > 0 { item.rating = r }
            }
        }
        try? context.save()
    }
}
