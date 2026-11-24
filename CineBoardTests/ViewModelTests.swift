import SwiftData
import XCTest

@testable import CineBoard

@MainActor
final class ViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var deps: AppDependencies!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try ModelContainer(
            for: UserAccount.self, MovieCollection.self, CollectionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        deps = .local(
            context: context, catalog: StubCatalog(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    private func movie(_ id: Int) -> Movie {
        Movie(
            id: id, title: "Фильм \(id)", overview: nil, posterPath: "/p\(id).jpg", backdropPath: nil,
            releaseDate: "2020-05-01", voteAverage: 7.5, runtime: nil, genres: nil)
    }

    private func signUp(_ name: String) throws -> UserAccount {
        try deps.session.register(username: name, password: "password1")
        return deps.session.currentUser!
    }

    // MARK: CollectionsViewModel

    func testCollectionsViewModelSplitsMineAndOthers() throws {
        DemoSeeder.seedIfNeeded(context)
        let me = try signUp("ivan")
        _ = try deps.collections.create(title: "Моя", details: "", isPublic: false, as: me)
        let model = deps.makeCollectionsViewModel()

        XCTAssertEqual(model.scope, .mine)
        XCTAssertEqual(model.visible.map(\.title), ["Моя"])
        model.scope = .discover
        XCTAssertEqual(model.visible.count, 3)
        XCTAssertFalse(model.visible.contains { $0.owner?.id == me.id })
    }

    func testCollectionsViewModelIsEmptyWithoutUser() {
        let model = deps.makeCollectionsViewModel()
        XCTAssertTrue(model.mine.isEmpty)
    }

    // MARK: CollectionEditorViewModel

    func testEditorValidatesAndCreates() throws {
        _ = try signUp("julia")
        let editor = deps.makeEditorViewModel(collection: nil)
        XCTAssertFalse(editor.canSave)
        editor.title = "  "
        XCTAssertNil(editor.save())
        XCTAssertNotNil(editor.errorMessage)

        editor.title = "  Нуар "
        editor.isPublic = false
        let created = editor.save()
        XCTAssertEqual(created?.title, "Нуар")
        XCTAssertEqual(created?.isPublic, false)
    }

    func testEditorUpdatesExisting() throws {
        let me = try signUp("kate")
        let c = try deps.collections.create(title: "Старое", details: "", isPublic: true, as: me)
        let editor = deps.makeEditorViewModel(collection: c)
        XCTAssertEqual(editor.title, "Старое")
        editor.title = "Новое"
        XCTAssertIdentical(editor.save(), c)
        XCTAssertEqual(c.title, "Новое")
    }

    // MARK: SaveToCollectionViewModel

    func testSaveViewModelTogglesMovie() throws {
        let me = try signUp("leo")
        let c = try deps.collections.create(title: "A", details: "", isPublic: true, as: me)
        let model = deps.makeSaveViewModel(movie: movie(5))
        XCTAssertFalse(model.contains(c))
        model.toggle(c)
        XCTAssertTrue(model.contains(c))
        model.toggle(c)
        XCTAssertFalse(model.contains(c))
        XCTAssertNil(model.errorMessage)
    }

    func testSaveViewModelListsOnlyMyCollections() throws {
        let a = try signUp("mia")
        _ = try deps.collections.create(title: "Мия", details: "", isPublic: true, as: a)
        _ = try signUp("nick")
        let model = deps.makeSaveViewModel(movie: movie(1))
        XCTAssertTrue(model.mine.isEmpty)
    }

    // MARK: CollectionDetailViewModel

    func testDetailViewModelOwnerAndVisitor() throws {
        let owner = try signUp("olga")
        let c = try deps.collections.create(title: "Приватная", details: "", isPublic: false, as: owner)
        try deps.collections.add(movie(1), to: c, as: owner)

        let ownerModel = deps.makeCollectionDetailViewModel(c)
        XCTAssertTrue(ownerModel.isOwner)
        XCTAssertEqual(ownerModel.availability, .available)
        XCTAssertEqual(ownerModel.movies.map(\.id), [1])

        _ = try signUp("paul")
        let visitor = deps.makeCollectionDetailViewModel(c)
        XCTAssertFalse(visitor.isOwner)
        XCTAssertEqual(visitor.availability, .privateToViewer)
        visitor.remove(movieID: 1)
        XCTAssertNotNil(visitor.errorMessage)
        XCTAssertEqual(c.items.count, 1)
    }

    func testDetailViewModelDeleteMarksRemoved() throws {
        let me = try signUp("quinn")
        let c = try deps.collections.create(title: "Удалить", details: "", isPublic: true, as: me)
        let model = deps.makeCollectionDetailViewModel(c)
        XCTAssertTrue(model.delete())
        XCTAssertEqual(model.availability, .removed)
    }

    // MARK: MovieListModel

    private func page(_ ids: [Int], page: Int, of total: Int) -> MoviePage {
        MoviePage(page: page, results: ids.map(movie), totalPages: total)
    }

    func testMovieListPaginationDeduplicates() async {
        let model = MovieListModel { [self] p in
            p == 1 ? await page([1, 2, 3], page: 1, of: 2) : await page([3, 4], page: 2, of: 2)
        }
        await model.loadFirst()
        XCTAssertEqual(model.phase, .loaded)
        await model.loadMoreIfNeeded(current: model.movies.last!)
        XCTAssertEqual(model.movies.map(\.id), [1, 2, 3, 4])
    }

    func testMovieListEmptyAndFailure() async {
        let empty = MovieListModel { [self] _ in await page([], page: 1, of: 1) }
        await empty.loadFirst()
        XCTAssertEqual(empty.phase, .empty)

        let failing = MovieListModel { _ in throw TMDBError.offline }
        await failing.loadFirst()
        XCTAssertEqual(failing.phase, .failed(TMDBError.offline.errorDescription!))
    }

    func testMovieListRefreshKeepsDataOnError() async {
        nonisolated(unsafe) var fail = false
        let model = MovieListModel { [self] _ in
            if fail { throw TMDBError.offline }
            return await page([1, 2], page: 1, of: 1)
        }
        await model.loadFirst()
        fail = true
        await model.refresh()
        XCTAssertEqual(model.movies.map(\.id), [1, 2])
        XCTAssertEqual(model.phase, .loaded)
    }
}

private struct StubCatalog: MovieCatalog {
    var isConfigured: Bool { true }
    func trending(page: Int) async throws -> MoviePage { MoviePage(page: 1, results: [], totalPages: 1) }
    func search(query: String, page: Int) async throws -> MoviePage { MoviePage(page: 1, results: [], totalPages: 1) }
    func details(id: Int) async throws -> Movie { throw TMDBError.badResponse }
}
