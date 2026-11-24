import SwiftData
import XCTest

@testable import CineBoard

@MainActor
final class SocialTests: XCTestCase {
    private var container: ModelContainer!
    private var deps: AppDependencies!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try AppSchema.makeContainer(inMemory: true)
        deps = .local(context: context, defaults: UserDefaults(suiteName: UUID().uuidString)!)
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

    // MARK: Отзывы

    func testSaveReviewUpdatesInsteadOfDuplicating() throws {
        let me = try signUp("rita")
        let first = try deps.reviews.save(movie: movie(1), rating: 7, text: "  норм  ", as: me)
        XCTAssertEqual(first.text, "норм")
        let second = try deps.reviews.save(movie: movie(1), rating: 9, text: "лучше", as: me)
        XCTAssertIdentical(first, second)
        XCTAssertEqual(deps.reviews.reviews(forMovie: 1).count, 1)
        XCTAssertEqual(deps.reviews.reviews(forMovie: 1).first?.rating, 9)
    }

    func testReviewValidation() throws {
        let me = try signUp("sam")
        for bad in [0, 11, -1] {
            XCTAssertThrowsError(try deps.reviews.save(movie: movie(1), rating: bad, text: "", as: me)) {
                XCTAssertEqual($0 as? ReviewError, .invalidRating)
            }
        }
        let long = String(repeating: "а", count: ReviewRules.maxTextLength + 1)
        XCTAssertThrowsError(try deps.reviews.save(movie: movie(1), rating: 5, text: long, as: me)) {
            XCTAssertEqual($0 as? ReviewError, .textTooLong)
        }
        // Оценка без текста допустима.
        XCTAssertNoThrow(try deps.reviews.save(movie: movie(1), rating: 5, text: "", as: me))
        XCTAssertTrue(deps.reviews.reviews(by: me).first?.text.isEmpty ?? false)
    }

    func testCommunityRatingAverages() throws {
        XCTAssertNil(deps.reviews.communityRating(forMovie: 3))
        let a = try signUp("tom")
        _ = try deps.reviews.save(movie: movie(3), rating: 8, text: "", as: a)
        let b = try signUp("uma")
        _ = try deps.reviews.save(movie: movie(3), rating: 5, text: "", as: b)
        XCTAssertEqual(deps.reviews.communityRating(forMovie: 3), CommunityRating(average: 6.5, count: 2))
        XCTAssertNil(deps.reviews.communityRating(forMovie: 4))
    }

    func testOnlyAuthorCanDeleteReview() throws {
        let a = try signUp("vera")
        let review = try deps.reviews.save(movie: movie(1), rating: 6, text: "", as: a)
        let b = try signUp("walt")
        XCTAssertThrowsError(try deps.reviews.delete(review, as: b)) {
            XCTAssertEqual($0 as? ReviewError, .notAuthor)
        }
        try deps.reviews.delete(review, as: a)
        XCTAssertTrue(deps.reviews.reviews(forMovie: 1).isEmpty)
    }

    func testDeletingUserCascadesToReviewsAndFavorites() throws {
        let me = try signUp("xena")
        _ = try deps.reviews.save(movie: movie(1), rating: 6, text: "", as: me)
        try deps.favorites.add(movie(1), as: me)
        context.delete(me)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Review>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FavoriteMovie>()), 0)
    }

    // MARK: Любимые

    func testFavoritesAddRemoveOrderAndLimit() throws {
        let me = try signUp("yuri")
        for id in 1...FavoritesRules.limit { try deps.favorites.add(movie(id), as: me) }
        try deps.favorites.add(movie(1), as: me)  // повтор — без эффекта
        XCTAssertEqual(deps.favorites.favorites(of: me).count, FavoritesRules.limit)
        XCTAssertThrowsError(try deps.favorites.add(movie(99), as: me)) {
            XCTAssertEqual($0 as? FavoritesError, .limitReached)
        }
        try deps.favorites.remove(movieID: 1, as: me)
        XCTAssertFalse(deps.favorites.isFavorite(movieID: 1, of: me))
        XCTAssertEqual(deps.favorites.favorites(of: me).map(\.position), Array(0..<(FavoritesRules.limit - 1)))
        try deps.favorites.add(movie(99), as: me)
        XCTAssertEqual(deps.favorites.favorites(of: me).last?.movieID, 99)
    }

    func testFavoritesMove() throws {
        let me = try signUp("zoe")
        for id in 1...4 { try deps.favorites.add(movie(id), as: me) }
        try deps.favorites.move(from: IndexSet(integer: 0), to: 3, as: me)
        XCTAssertEqual(deps.favorites.favorites(of: me).map(\.movieID), [2, 3, 1, 4])
        try deps.favorites.move(from: IndexSet(integer: 3), to: 0, as: me)
        XCTAssertEqual(deps.favorites.favorites(of: me).map(\.movieID), [4, 2, 3, 1])
    }

    func testFavoritesArePerUser() throws {
        let a = try signUp("abby")
        try deps.favorites.add(movie(1), as: a)
        let b = try signUp("bill")
        XCTAssertTrue(deps.favorites.favorites(of: b).isEmpty)
        XCTAssertEqual(deps.favorites.favorites(of: a).count, 1)
    }

    // MARK: ViewModel'и

    func testMovieDetailViewModelReviewsAndFavorite() throws {
        let me = try signUp("cara")
        let other = try signUp("dean")
        _ = try deps.reviews.save(movie: movie(5), rating: 4, text: "так себе", as: other)
        try deps.session.login(username: "cara", password: "password1")
        XCTAssertEqual(deps.session.currentUser?.id, me.id)

        let model = deps.makeMovieDetailViewModel(movie(5))
        XCTAssertNil(model.myReview)
        XCTAssertEqual(model.otherReviews.count, 1)
        XCTAssertEqual(model.communityRating?.count, 1)

        _ = try deps.reviews.save(movie: movie(5), rating: 10, text: "шедевр", as: me)
        XCTAssertEqual(model.myReview?.rating, 10)
        XCTAssertEqual(model.otherReviews.count, 1)  // свой отзыв не дублируется в общем списке
        XCTAssertEqual(model.communityRating, CommunityRating(average: 7, count: 2))

        XCTAssertFalse(model.isFavorite)
        model.toggleFavorite()
        XCTAssertTrue(model.isFavorite)
        model.toggleFavorite()
        XCTAssertFalse(model.isFavorite)
    }

    func testReviewEditorViewModel() throws {
        _ = try signUp("emil")
        let editor = deps.makeReviewEditorViewModel(movie: movie(7))
        XCTAssertFalse(editor.canSave)  // оценка не выбрана
        editor.rating = 8
        XCTAssertTrue(editor.canSave)
        editor.text = String(repeating: "x", count: ReviewRules.maxTextLength + 1)
        XCTAssertFalse(editor.canSave)
        editor.text = "хорошо"
        XCTAssertTrue(editor.save())

        let again = deps.makeReviewEditorViewModel(movie: movie(7))
        XCTAssertTrue(again.isEditing)
        XCTAssertEqual(again.rating, 8)
        XCTAssertEqual(again.text, "хорошо")
        XCTAssertTrue(again.delete())
        XCTAssertNil(deps.makeMovieDetailViewModel(movie(7)).myReview)
    }

    func testProfileViewModelOwnerAndVisitor() throws {
        let me = try signUp("fred")
        try deps.favorites.add(movie(1), as: me)
        try deps.favorites.add(movie(2), as: me)
        _ = try deps.collections.create(title: "Публичная", details: "", isPublic: true, as: me)
        _ = try deps.collections.create(title: "Скрытая", details: "", isPublic: false, as: me)

        let own = deps.makeProfileViewModel(user: me)
        XCTAssertTrue(own.isMe)
        XCTAssertEqual(own.collections.count, 2)
        own.moveFavorites(from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(own.favorites.map(\.movieID), [2, 1])

        _ = try signUp("gina")
        let visitor = deps.makeProfileViewModel(user: me)
        XCTAssertFalse(visitor.isMe)
        XCTAssertEqual(visitor.collections.map(\.title), ["Публичная"])
        visitor.removeFavorite(movieID: 2)  // чужой профиль менять нельзя
        XCTAssertEqual(visitor.favorites.count, 2)
    }

    // MARK: Демо-данные

    func testDemoSocialSeedIsIdempotentAndVisible() throws {
        DemoSeeder.seedIfNeeded(context)
        DemoSeeder.seedIfNeeded(context)
        let anna = try context.fetch(FetchDescriptor<UserAccount>()).first { $0.username == "anna_films" }!
        XCTAssertEqual(anna.reviews.count, 3)
        XCTAssertEqual(anna.favorites.count, 4)
        // «Паразиты» оценили оба демо-пользователя.
        XCTAssertEqual(deps.reviews.communityRating(forMovie: 496243)?.count, 2)
    }
}
