import SwiftData
import XCTest

@testable import CineBoard

@MainActor
final class CollectionCardsTests: XCTestCase {
    private var container: ModelContainer!
    private var deps: AppDependencies!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try AppSchema.makeContainer(inMemory: true)
        deps = .local(context: context, catalog: UITestCatalog(), secrets: InMemorySecretStore())
    }

    private func signUp(_ name: String) throws -> UserAccount {
        try deps.session.register(username: name, password: "password1")
        return deps.session.currentUser!
    }

    private func makeCollections(_ count: Int, for user: UserAccount, isPublic: Bool = true) throws -> [MovieCollection] {
        var list: [MovieCollection] = []
        for i in 1...count {
            let c = try deps.collections.create(title: "C\(i)", details: "", isPublic: isPublic, as: user)
            c.createdAt = Date(timeIntervalSince1970: 1_000 + Double(i))  // C1 старее всех
            list.append(c)
        }
        try context.save()
        return list
    }

    // MARK: Цветовые темы

    func testThemeResolutionIsStableAndOverridable() throws {
        let me = try signUp("tess")
        let c = try deps.collections.create(title: "Noir", details: "", isPublic: true, as: me)
        let auto = CollectionTheme.resolve(for: c)
        XCTAssertEqual(CollectionTheme.resolve(for: c), auto, "без выбора цвет стабилен")
        XCTAssertTrue(CollectionTheme.all.contains(auto))

        try deps.collections.setTheme("ocean", of: c, as: me)
        XCTAssertEqual(CollectionTheme.resolve(for: c).id, "ocean")
        c.themeID = "unknown-theme"
        XCTAssertEqual(CollectionTheme.resolve(for: c), auto, "неизвестная тема → автоматический цвет")
    }

    func testThemePaletteIsConsistent() {
        let ids = CollectionTheme.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "id тем уникальны")
        XCTAssertGreaterThanOrEqual(ids.count, 8)
        XCTAssertNotNil(CollectionTheme.theme(withID: "violet"))
    }

    func testOnlyOwnerCanSetTheme() throws {
        let owner = try signUp("uri")
        let c = try deps.collections.create(title: "Mine", details: "", isPublic: true, as: owner)
        let other = try signUp("val")
        XCTAssertThrowsError(try deps.collections.setTheme("rose", of: c, as: other)) {
            XCTAssertEqual($0 as? CollectionError, .notOwner)
        }
        XCTAssertNotEqual(c.themeID, "rose")
    }

    func testEditorSavesChosenTheme() throws {
        let me = try signUp("wyn")
        let editor = deps.makeEditorViewModel(collection: nil)
        XCTAssertEqual(editor.themeID, CollectionTheme.all[2].id)  // стартовый цвет для новой подборки
        editor.title = "Colorful"
        editor.themeID = "crimson"
        let created = try XCTUnwrap(editor.save())
        XCTAssertEqual(created.themeID, "crimson")

        let again = deps.makeEditorViewModel(collection: created)
        XCTAssertEqual(again.themeID, "crimson")
        again.themeID = "gold"
        XCTAssertNotNil(again.save())
        XCTAssertEqual(created.themeID, "gold")
        XCTAssertTrue(me.collections.contains { $0.id == created.id })
    }

    // MARK: Закрепление и «только три»

    func testProfileShowsNewestThreeWhenNothingPinned() throws {
        let me = try signUp("xan")
        _ = try makeCollections(5, for: me)
        let model = deps.makeProfileViewModel(user: me)
        XCTAssertEqual(model.featuredCollections.map(\.title), ["C5", "C4", "C3"])
        XCTAssertEqual(model.collections.count, 5)
        XCTAssertTrue(model.hasMoreCollections)

        let few = try signUp("yan")
        _ = try makeCollections(2, for: few)
        XCTAssertFalse(deps.makeProfileViewModel(user: few).hasMoreCollections)
    }

    func testPinnedCollectionsOverrideAndOrder() throws {
        let me = try signUp("zia")
        let list = try makeCollections(5, for: me)  // C1…C5
        try deps.collections.pin(list[0], as: me)  // C1
        try deps.collections.pin(list[3], as: me)  // C4
        let model = deps.makeProfileViewModel(user: me)
        XCTAssertEqual(model.featuredCollections.map(\.title), ["C1", "C4"], "только закреплённые, по порядку")
        XCTAssertEqual(model.pinnedCollections.map(\.title), ["C1", "C4"])
        XCTAssertEqual(Set(model.unpinnedCollections.map(\.title)), ["C2", "C3", "C5"])

        try deps.collections.movePinned(from: IndexSet(integer: 1), to: 0, as: me)
        XCTAssertEqual(model.featuredCollections.map(\.title), ["C4", "C1"])
    }

    func testPinLimitUnpinAndRenumbering() throws {
        let me = try signUp("abe")
        let list = try makeCollections(5, for: me)
        for c in list.prefix(CollectionRules.profileLimit) { try deps.collections.pin(c, as: me) }
        XCTAssertThrowsError(try deps.collections.pin(list[3], as: me)) {
            XCTAssertEqual($0 as? CollectionError, .pinLimitReached)
        }
        XCTAssertNoThrow(try deps.collections.pin(list[0], as: me), "повторное закрепление безопасно")

        try deps.collections.unpin(list[0], as: me)
        XCTAssertEqual(list[1].pinPosition, 0)  // позиции плотные
        XCTAssertEqual(list[2].pinPosition, 1)
        XCTAssertEqual(list[0].pinPosition, -1)
        XCTAssertNoThrow(try deps.collections.pin(list[3], as: me))
        XCTAssertEqual(list[3].pinPosition, 2)

        // Удаление закреплённой подборки тоже держит порядок плотным.
        try deps.collections.delete(list[1], as: me)
        XCTAssertEqual(list[2].pinPosition, 0)
        XCTAssertEqual(list[3].pinPosition, 1)
    }

    func testOnlyOwnerCanPinAndViewModelIgnoresVisitors() throws {
        let owner = try signUp("bea")
        let c = try makeCollections(1, for: owner)[0]
        let other = try signUp("cal")
        XCTAssertThrowsError(try deps.collections.pin(c, as: other)) {
            XCTAssertEqual($0 as? CollectionError, .notOwner)
        }
        deps.makeProfileViewModel(user: owner).pin(c)  // чужой профиль — без эффекта
        XCTAssertEqual(c.pinPosition, -1)
    }

    func testVisitorSeesOnlyVisiblePinnedCollections() throws {
        let owner = try signUp("dee")
        let list = try makeCollections(4, for: owner)
        try deps.collections.update(list[0], title: "C1", details: "", isPublic: false, as: owner)
        try deps.collections.pin(list[0], as: owner)  // приватная
        try deps.collections.pin(list[1], as: owner)
        _ = try signUp("eli")
        let model = deps.makeProfileViewModel(user: owner)
        XCTAssertEqual(model.featuredCollections.map(\.title), ["C2"], "приватную закреплённую посторонний не видит")
        XCTAssertEqual(model.collections.count, 3)
        XCTAssertTrue(model.hasMoreCollections)
    }

    func testPrivateProfileFeaturedIsEmptyForVisitors() throws {
        let owner = try signUp("fay")
        _ = try makeCollections(2, for: owner)
        try deps.session.updateProfile(ProfileEdit(displayName: "", bio: "", isPrivate: true))
        _ = try signUp("gil")
        XCTAssertTrue(deps.makeProfileViewModel(user: owner).featuredCollections.isEmpty)
    }

    // MARK: Отзывы и сохранение в профиле

    func testReviewsShowThreeWithMoreLink() throws {
        let me = try signUp("hal")
        for id in 1...5 {
            let movie = Movie(
                id: id, title: "M\(id)", overview: nil, posterPath: nil, backdropPath: nil, releaseDate: "2020",
                voteAverage: nil, runtime: nil, genres: nil)
            let review = try deps.reviews.save(movie: movie, rating: 7, text: "", as: me)
            review.updatedAt = Date(timeIntervalSince1970: 1_000 + Double(id))
        }
        try context.save()
        let model = deps.makeProfileViewModel(user: me)
        XCTAssertEqual(model.featuredReviews.map(\.movieTitle), ["M5", "M4", "M3"])
        XCTAssertEqual(model.reviews.count, 5)
        XCTAssertTrue(model.hasMoreReviews)
    }

    func testSavingFromProfileCardsOnlyForOthersCollections() throws {
        let owner = try signUp("ian")
        let c = try makeCollections(1, for: owner)[0]
        let visitor = try signUp("jem")
        let model = deps.makeProfileViewModel(user: owner)
        XCTAssertTrue(model.canSave(c))
        XCTAssertFalse(model.isSaved(c))
        model.toggleSave(c)
        XCTAssertTrue(model.isSaved(c))
        XCTAssertEqual(deps.social.savedCollections(of: visitor).count, 1)
        model.toggleSave(c)
        XCTAssertFalse(model.isSaved(c))

        try deps.session.login(username: "ian", password: "password1")
        XCTAssertFalse(model.canSave(c), "свои подборки сохранять не нужно")
    }
}
