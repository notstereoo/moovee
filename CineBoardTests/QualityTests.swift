import SwiftData
import XCTest

@testable import CineBoard

private final class FakeCatalog: MovieCatalog, @unchecked Sendable {
    var failure: Error?
    var titleSuffix = ""
    private(set) var detailsCalls = 0
    var isConfigured: Bool { true }

    private func movie(_ id: Int, poster: String? = nil) -> Movie {
        Movie(
            id: id, title: "Фильм \(id)\(titleSuffix)", overview: nil, posterPath: poster ?? "/new\(id).jpg",
            backdropPath: nil, releaseDate: "2021-01-01", voteAverage: 8.1, runtime: nil, genres: nil)
    }

    func trending(page: Int) async throws -> MoviePage {
        if let failure { throw failure }
        return MoviePage(page: page, results: [movie(1), movie(2)], totalPages: 3)
    }

    func search(query: String, page: Int) async throws -> MoviePage {
        if let failure { throw failure }
        return MoviePage(page: page, results: [movie(9)], totalPages: 1)
    }

    func details(id: Int) async throws -> Movie {
        detailsCalls += 1
        if let failure { throw failure }
        return movie(id)
    }
}

@MainActor
final class QualityTests: XCTestCase {
    private var container: ModelContainer!
    private var deps: AppDependencies!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try AppSchema.makeContainer(inMemory: true)
        deps = .local(context: context, catalog: FakeCatalog(), secrets: InMemorySecretStore())
    }

    private func movie(_ id: Int, title: String? = nil, year: String? = "2020", rating: Double? = 7) -> Movie {
        Movie(
            id: id, title: title ?? "Фильм \(id)", overview: nil, posterPath: "/old\(id).jpg", backdropPath: nil,
            releaseDate: year, voteAverage: rating, runtime: nil, genres: nil)
    }

    private func signUp(_ name: String) throws -> UserAccount {
        try deps.session.register(username: name, password: "password1")
        return deps.session.currentUser!
    }

    // MARK: Кэш каталога

    func testCacheFallsBackWhenOffline() async throws {
        let fake = FakeCatalog()
        let catalog = CachingCatalog(base: fake, cache: MemoryCatalogCache())

        let fresh = try await catalog.trending(page: 1)
        XCTAssertFalse(fresh.isFromCache)

        fake.failure = TMDBError.offline
        let stale = try await catalog.trending(page: 1)
        XCTAssertTrue(stale.isFromCache)
        XCTAssertEqual(stale.results.map(\.id), [1, 2])
        XCTAssertEqual(stale.totalPages, 3)

        // Страница, которой нет в кэше, — ошибка как есть.
        do {
            _ = try await catalog.trending(page: 2)
            XCTFail("expected error")
        } catch { XCTAssertEqual(error as? TMDBError, .offline) }
    }

    func testCacheDoesNotMaskConfigurationErrors() async throws {
        let fake = FakeCatalog()
        let catalog = CachingCatalog(base: fake, cache: MemoryCatalogCache())
        _ = try await catalog.details(id: 5)
        fake.failure = TMDBError.invalidKey
        do {
            _ = try await catalog.details(id: 5)
            XCTFail("expected error")
        } catch { XCTAssertEqual(error as? TMDBError, .invalidKey) }
        fake.failure = TMDBError.server(503)
        let cachedDetails = try await catalog.details(id: 5)
        XCTAssertEqual(cachedDetails.id, 5)
    }

    func testSearchCacheIsPerQuery() async throws {
        let fake = FakeCatalog()
        let catalog = CachingCatalog(base: fake, cache: MemoryCatalogCache())
        _ = try await catalog.search(query: "Матрица", page: 1)
        fake.failure = TMDBError.offline
        let hit = try await catalog.search(query: "матрица", page: 1)
        XCTAssertTrue(hit.isFromCache)
        do {
            _ = try await catalog.search(query: "другое", page: 1)
            XCTFail("expected error")
        } catch { XCTAssertEqual(error as? TMDBError, .offline) }
    }

    func testDiskCacheRoundTripAndPrune() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = DiskCatalogCache(directory: dir)
        cache.store(Data("a".utf8), for: "k")
        XCTAssertEqual(cache.data(for: "k"), Data("a".utf8))
        XCTAssertNil(cache.data(for: "other"))
        // Новый экземпляр с нулевым сроком хранения очищает старые файлы.
        _ = DiskCatalogCache(directory: dir, maxAge: -1)
        XCTAssertNil(cache.data(for: "k"))
    }

    func testMovieListShowsCachedBanner() async {
        let fake = FakeCatalog()
        let catalog = CachingCatalog(base: fake, cache: MemoryCatalogCache())
        let model = MovieListModel { try await catalog.trending(page: $0) }
        await model.loadFirst()
        XCTAssertFalse(model.isShowingCached)
        fake.failure = TMDBError.offline
        await model.refresh()
        XCTAssertTrue(model.isShowingCached)
        XCTAssertEqual(model.phase, .loaded)
    }

    // MARK: Обновление снимков

    func testSnapshotRefresherUpdatesAllSnapshotTypes() async throws {
        let me = try signUp("lena")
        let fake = FakeCatalog()
        fake.titleSuffix = " (новое)"
        let c = try deps.collections.create(title: "A", details: "", isPublic: true, as: me)
        try deps.collections.add(movie(1), to: c, as: me)
        _ = try deps.reviews.save(movie: movie(1), rating: 7, text: "", as: me)
        try deps.favorites.add(movie(2), as: me)

        let now = Date()
        let count = await SnapshotRefresher.refreshStale(context: context, catalog: fake, now: now)
        XCTAssertEqual(count, 2)  // уникальные фильмы: 1 и 2
        XCTAssertEqual(c.items.first?.title, "Фильм 1 (новое)")
        XCTAssertEqual(c.items.first?.posterPath, "/new1.jpg")
        XCTAssertEqual(c.items.first?.rating, 8.1)
        XCTAssertEqual(me.reviews.first?.movieTitle, "Фильм 1 (новое)")
        XCTAssertEqual(me.favorites.first?.posterPath, "/new2.jpg")

        // Свежие снимки повторно не запрашиваются…
        let callsBefore = fake.detailsCalls
        let again = await SnapshotRefresher.refreshStale(context: context, catalog: fake, now: now.addingTimeInterval(3600))
        XCTAssertEqual(again, 0)
        XCTAssertEqual(fake.detailsCalls, callsBefore)
        // …а через неделю — снова.
        let later = await SnapshotRefresher.refreshStale(
            context: context, catalog: fake, now: now.addingTimeInterval(SnapshotRefresher.maxAge + 60))
        XCTAssertEqual(later, 2)
    }

    func testSnapshotRefresherSurvivesErrorsAndRespectsBatch() async throws {
        let me = try signUp("mark")
        let c = try deps.collections.create(title: "A", details: "", isPublic: true, as: me)
        for id in 1...5 { try deps.collections.add(movie(id), to: c, as: me) }

        let fake = FakeCatalog()
        fake.failure = TMDBError.offline
        let failed = await SnapshotRefresher.refreshStale(context: context, catalog: fake)
        XCTAssertEqual(failed, 0)
        XCTAssertTrue(c.items.allSatisfy { $0.refreshedAt == nil })  // повторим при следующем запуске

        fake.failure = nil
        let limited = await SnapshotRefresher.refreshStale(context: context, catalog: fake, batchSize: 3)
        XCTAssertEqual(limited, 3)
        XCTAssertEqual(c.items.filter { $0.refreshedAt != nil }.count, 3)
    }

    // MARK: Подборка: сортировка, поиск, порядок

    private func filledCollection() throws -> (UserAccount, MovieCollection) {
        let me = try signUp("nora")
        let c = try deps.collections.create(title: "A", details: "", isPublic: true, as: me)
        try deps.collections.add(movie(1, title: "Бета", year: "2010", rating: 6), to: c, as: me)
        try deps.collections.add(movie(2, title: "Альфа", year: "2020", rating: 9), to: c, as: me)
        try deps.collections.add(movie(3, title: "Гамма", year: nil, rating: nil), to: c, as: me)
        // Разные даты добавления — детерминированный порядок «сначала новые».
        for (i, item) in c.items.sorted(by: { $0.movieID < $1.movieID }).enumerated() {
            item.addedAt = Date(timeIntervalSince1970: Double(1000 + i))
        }
        return (me, c)
    }

    func testSortModes() throws {
        let (_, c) = try filledCollection()
        func ids(_ s: CollectionSort) -> [Int] { c.items(sortedBy: s).map(\.movieID) }
        XCTAssertEqual(ids(.added), [3, 2, 1])
        XCTAssertEqual(ids(.title), [2, 1, 3])  // Альфа, Бета, Гамма
        XCTAssertEqual(ids(.year), [2, 1, 3])  // 2020, 2010, без года — в конце
        XCTAssertEqual(ids(.rating), [2, 1, 3])  // 9, 6, без рейтинга — в конце
        XCTAssertEqual(ids(.manual), [1, 2, 3])  // порядок добавления
    }

    func testMoveItemsChangesManualOrderOnlyForOwner() throws {
        let (me, c) = try filledCollection()
        try deps.collections.moveItems(in: c, from: IndexSet(integer: 2), to: 0, as: me)
        XCTAssertEqual(c.items(sortedBy: .manual).map(\.movieID), [3, 1, 2])

        let intruder = try signUp("oleg")
        XCTAssertThrowsError(try deps.collections.moveItems(in: c, from: IndexSet(integer: 0), to: 2, as: intruder)) {
            XCTAssertEqual($0 as? CollectionError, .notOwner)
        }
        XCTAssertEqual(c.items(sortedBy: .manual).map(\.movieID), [3, 1, 2])
    }

    func testDetailViewModelSearchSortAndReorder() throws {
        let (_, c) = try filledCollection()
        let model = deps.makeCollectionDetailViewModel(c)
        XCTAssertEqual(model.movies.map(\.id), [3, 2, 1])

        model.sort = .title
        XCTAssertEqual(model.movies.map(\.title), ["Альфа", "Бета", "Гамма"])

        model.query = "  ГАМ "
        XCTAssertTrue(model.isSearching)
        XCTAssertEqual(model.movies.map(\.id), [3])
        model.query = "нет такого"
        XCTAssertTrue(model.movies.isEmpty)
        model.query = ""
        XCTAssertFalse(model.isSearching)

        model.moveItems(from: IndexSet(integer: 0), to: 3)  // первый → в конец
        XCTAssertEqual(model.sort, .manual)
        XCTAssertEqual(model.movies.map(\.id), [2, 3, 1])
    }

    func testNewItemGoesToEndOfManualOrder() throws {
        let (me, c) = try filledCollection()
        try deps.collections.moveItems(in: c, from: IndexSet(integer: 2), to: 0, as: me)  // [3,1,2]
        try deps.collections.add(movie(4), to: c, as: me)
        XCTAssertEqual(c.items(sortedBy: .manual).map(\.movieID), [3, 1, 2, 4])
    }
}
