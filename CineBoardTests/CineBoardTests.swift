import XCTest
import SwiftData
@testable import CineBoard

@MainActor
final class CineBoardTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try AppSchema.makeContainer(inMemory: true)
    }

    private func makeSession() -> AppSession {
        AppSession(context: context, defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    private func movie(_ id: Int = 1) -> Movie {
        Movie(
            id: id, title: "Фильм \(id)", overview: nil, posterPath: "/p\(id).jpg", backdropPath: nil,
            releaseDate: "2020-05-01", voteAverage: 7.5, runtime: nil, genres: nil)
    }

    // MARK: Аккаунт

    func testRegisterLoginLogout() throws {
        let s = makeSession()
        try s.register(username: "Alice_1", password: "password1")
        XCTAssertEqual(s.currentUser?.username, "alice_1")
        s.logout()
        XCTAssertNil(s.currentUser)
        XCTAssertThrowsError(try s.login(username: "alice_1", password: "wrongpass")) {
            XCTAssertEqual($0 as? AuthError, .invalidCredentials)
        }
        try s.login(username: "ALICE_1", password: "password1")
        XCTAssertNotNil(s.currentUser)
    }

    func testRegistrationValidationAndDuplicates() throws {
        let s = makeSession()
        XCTAssertThrowsError(try s.register(username: "a", password: "password1")) {
            XCTAssertEqual($0 as? AuthError, .invalidUsername)
        }
        XCTAssertThrowsError(try s.register(username: "bob", password: "short")) {
            XCTAssertEqual($0 as? AuthError, .weakPassword)
        }
        try s.register(username: "bob", password: "password1")
        XCTAssertThrowsError(try s.register(username: "BOB", password: "password2")) {
            XCTAssertEqual($0 as? AuthError, .usernameTaken)
        }
    }

    func testDemoUsersCannotLogIn() throws {
        DemoSeeder.seedIfNeeded(context)
        let s = makeSession()
        XCTAssertThrowsError(try s.login(username: "anna_films", password: "anything123")) {
            XCTAssertEqual($0 as? AuthError, .invalidCredentials)
        }
    }

    func testSessionRestoresAfterRelaunch() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let first = AppSession(context: context, defaults: defaults)
        try first.register(username: "carol", password: "password1")
        let second = AppSession(context: context, defaults: defaults)
        XCTAssertEqual(second.currentUser?.username, "carol")
    }

    // MARK: Коллекции и права

    func testCreateAddRemoveNoDuplicates() throws {
        let s = makeSession()
        try s.register(username: "dave", password: "password1")
        let me = s.currentUser!
        let repo = LocalCollectionRepository(context: context)
        let c = try repo.create(title: "Любимое", details: "", isPublic: true, as: me)
        try repo.add(movie(1), to: c, as: me)
        try repo.add(movie(1), to: c, as: me)
        XCTAssertEqual(c.items.count, 1)
        try repo.add(movie(2), to: c, as: me)
        try repo.remove(movieID: 1, from: c, as: me)
        XCTAssertEqual(c.items.map(\.movieID), [2])
        XCTAssertThrowsError(try repo.create(title: "   ", details: "", isPublic: true, as: me)) {
            XCTAssertEqual($0 as? CollectionError, .emptyTitle)
        }
    }

    func testSameMovieInSeveralCollections() throws {
        let s = makeSession()
        try s.register(username: "erin", password: "password1")
        let me = s.currentUser!
        let repo = LocalCollectionRepository(context: context)
        let a = try repo.create(title: "A", details: "", isPublic: true, as: me)
        let b = try repo.create(title: "B", details: "", isPublic: false, as: me)
        try repo.add(movie(7), to: a, as: me)
        try repo.add(movie(7), to: b, as: me)
        XCTAssertEqual(a.items.count, 1)
        XCTAssertEqual(b.items.count, 1)
    }

    func testOnlyOwnerCanModify() throws {
        let s = makeSession()
        try s.register(username: "owner1", password: "password1")
        let owner = s.currentUser!
        let repo = LocalCollectionRepository(context: context)
        let c = try repo.create(title: "Моя", details: "", isPublic: true, as: owner)

        try s.register(username: "intruder", password: "password1")
        let other = s.currentUser!
        XCTAssertThrowsError(try repo.update(c, title: "Взлом", details: "", isPublic: false, as: other)) {
            XCTAssertEqual($0 as? CollectionError, .notOwner)
        }
        XCTAssertThrowsError(try repo.delete(c, as: other)) { XCTAssertEqual($0 as? CollectionError, .notOwner) }
        XCTAssertThrowsError(try repo.add(movie(), to: c, as: other)) {
            XCTAssertEqual($0 as? CollectionError, .notOwner)
        }
        XCTAssertEqual(c.title, "Моя")
    }

    func testPrivateCollectionsHiddenFromOthers() throws {
        let s = makeSession()
        try s.register(username: "frank", password: "password1")
        let frank = s.currentUser!
        let repo = LocalCollectionRepository(context: context)
        _ = try repo.create(title: "Публичная", details: "", isPublic: true, as: frank)
        _ = try repo.create(title: "Приватная", details: "", isPublic: false, as: frank)

        try s.register(username: "grace", password: "password1")
        XCTAssertEqual(frank.collections(visibleTo: s.currentUser).map(\.title), ["Публичная"])
        XCTAssertEqual(frank.collections(visibleTo: frank).count, 2)
        XCTAssertEqual(frank.collections(visibleTo: nil).count, 1)
    }

    func testRepositoryQueriesAndRevision() throws {
        DemoSeeder.seedIfNeeded(context)
        let s = makeSession()
        try s.register(username: "henry", password: "password1")
        let me = s.currentUser!
        let repo = LocalCollectionRepository(context: context)
        XCTAssertEqual(repo.revision, 0)
        _ = try repo.create(title: "Моя", details: "", isPublic: true, as: me)
        _ = try repo.create(title: "Скрытая", details: "", isPublic: false, as: me)
        XCTAssertEqual(repo.revision, 2)
        XCTAssertEqual(repo.collections(ownedBy: me).count, 2)
        // Чужие: 3 публичных демо-подборки; приватные демо и свои не попадают.
        let others = repo.publicCollections(excluding: me)
        XCTAssertEqual(others.count, 3)
        XCTAssertTrue(others.allSatisfy { $0.isPublic && $0.owner?.id != me.id })
    }

    func testDemoSeedHasPrivateCollectionHiddenFromViewer() throws {
        DemoSeeder.seedIfNeeded(context)
        let s = makeSession()
        try s.register(username: "viewer", password: "password1")
        let anna = try context.fetch(FetchDescriptor<UserAccount>()).first { $0.username == "anna_films" }!
        XCTAssertEqual(anna.collections.count, 2)
        XCTAssertEqual(anna.collections(visibleTo: s.currentUser).count, 1)
    }

    // MARK: Каталог

    func testMovieDecoding() throws {
        let json = #"""
            {"page":1,"total_pages":3,"results":[{"id":603,"title":"Матрица","poster_path":"/m.jpg","release_date":"1999-03-30","vote_average":8.2,"overview":"…"}]}
            """#
        let page = try TMDBClient.decoder.decode(MoviePage.self, from: Data(json.utf8))
        XCTAssertEqual(page.totalPages, 3)
        XCTAssertEqual(page.results.first?.year, "1999")
        XCTAssertEqual(page.results.first?.posterPath, "/m.jpg")
    }

    func testClientWithoutKeyReportsMissingKey() async {
        let client = TMDBClient(apiKey: "")
        XCTAssertFalse(client.isConfigured)
        do { _ = try await client.trending(page: 1); XCTFail("expected error") } catch {
            XCTAssertEqual(error as? TMDBError, .missingKey)
        }
    }
}
