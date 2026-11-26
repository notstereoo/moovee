import SwiftData
import SwiftUI
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

    // MARK: Светлые и тёмные оттенки

    private func brightness(_ color: UIColor) -> CGFloat {
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
        return b
    }

    private func saturation(_ color: UIColor) -> CGFloat {
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
        return sat
    }

    func testEveryThemeIsLightInLightModeAndCalmInDark() {
        XCTAssertGreaterThanOrEqual(CollectionTheme.all.count, 30, "палитра заметно расширена")
        for theme in CollectionTheme.all {
            XCTAssertGreaterThan(brightness(theme.lightTop), 0.9, theme.id)
            XCTAssertGreaterThan(brightness(theme.lightBottom), 0.8, theme.id)
            XCTAssertLessThanOrEqual(brightness(theme.darkTop), 0.47, theme.id)
            XCTAssertLessThanOrEqual(brightness(theme.darkBottom), 0.27, theme.id)
            XCTAssertGreaterThan(brightness(theme.lightTop), brightness(theme.darkTop), theme.id)
            XCTAssertLessThanOrEqual(saturation(theme.darkTop), saturation(UIColor(hex: theme.baseTop)) + 0.001, theme.id)
        }
    }

    func testAlreadyDarkCalmThemesKeepTheirBrightnessInDarkMode() throws {
        for id in ["graphite", "slate"] {
            let theme = try XCTUnwrap(CollectionTheme.theme(withID: id))
            XCTAssertEqual(brightness(theme.darkBottom), brightness(UIColor(hex: theme.baseBottom)), accuracy: 0.01, id)
            XCTAssertEqual(
                brightness(theme.darkTop), min(brightness(UIColor(hex: theme.baseTop)), 0.46), accuracy: 0.01, id)
        }
    }

    func testAdaptiveColorsFollowInterfaceStyle() throws {
        let theme = try XCTUnwrap(CollectionTheme.theme(withID: "ocean"))
        let color = UIColor(theme.top)
        let light = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        XCTAssertEqual(light.rgbHex, theme.lightTop.rgbHex)
        XCTAssertEqual(dark.rgbHex, theme.darkTop.rgbHex)
        XCTAssertNotEqual(light.rgbHex, dark.rgbHex)
    }

    // MARK: Свои цвета

    func testCustomThemeCodesRoundTrip() throws {
        let code = CollectionTheme.customCode(top: 0xFF8800, bottom: 0x3355AA)
        XCTAssertEqual(code, "custom:FF8800-3355AA")
        let parsed = try XCTUnwrap(CollectionTheme.parseCustom(code))
        XCTAssertEqual(parsed.top, 0xFF8800)
        XCTAssertEqual(parsed.bottom, 0x3355AA)
        XCTAssertNotNil(CollectionTheme.parseCustom("FF8800-3355AA"), "без префикса тоже")
        for bad in ["", "custom:", "custom:FF8800", "custom:GG0000-111111", "custom:FF88-3355AA", "ember"] {
            XCTAssertNil(CollectionTheme.parseCustom(bad), bad)
        }
        XCTAssertTrue(CollectionTheme.isCustom(code))
        XCTAssertFalse(CollectionTheme.isCustom("ember"))
    }

    func testCustomColorsAreStoredOnCollectionAndVisibleToOthers() throws {
        let owner = try signUp("kit")
        let c = try deps.collections.create(title: "Mine", details: "", isPublic: true, as: owner)
        let code = CollectionTheme.customCode(top: 0x112233, bottom: 0xAABBCC)
        try deps.collections.setTheme(code, of: c, as: owner)

        _ = try signUp("lea")  // другой пользователь видит те же цвета
        let theme = CollectionTheme.resolve(for: c)
        XCTAssertEqual(theme.id, code)
        XCTAssertEqual(theme.baseTop, 0x112233)
        XCTAssertEqual(theme.baseBottom, 0xAABBCC)

        c.themeID = "custom:broken"  // битый код → безопасный цвет по умолчанию
        XCTAssertTrue(CollectionTheme.all.contains(CollectionTheme.resolve(for: c)))
    }

    func testEditorCustomColorFlow() throws {
        let me = try signUp("moe")
        let editor = deps.makeEditorViewModel(collection: nil)
        XCTAssertFalse(editor.isCustom)
        editor.selectCustom()  // стартует с текущих цветов
        XCTAssertTrue(editor.isCustom)
        editor.customTop = Color(UIColor(hex: 0x204060))
        editor.customBottom = Color(UIColor(hex: 0xA0C0E0))
        editor.customColorsChanged()
        XCTAssertEqual(editor.themeID, "custom:204060-A0C0E0")
        XCTAssertEqual(editor.currentTheme.baseTop, 0x204060)

        editor.title = "Palette"
        let created = try XCTUnwrap(editor.save())
        XCTAssertEqual(created.themeID, "custom:204060-A0C0E0")
        XCTAssertEqual(CollectionTheme.resolve(for: created).baseBottom, 0xA0C0E0)

        // Выбор готовой темы выходит из режима своих цветов.
        editor.select(CollectionTheme.all[0])
        XCTAssertFalse(editor.isCustom)
        XCTAssertTrue(me.collections.contains { $0.id == created.id })
    }

    // MARK: Личная палитра

    func testSavedPaletteRoundTripLimitAndDedup() throws {
        let me = try signUp("nia")
        let editor = deps.makeEditorViewModel(collection: nil)
        XCTAssertTrue(editor.savedThemes.isEmpty)
        XCTAssertFalse(editor.canSaveCustom, "готовую тему сохранять в «свои» нельзя")

        editor.selectCustom()
        XCTAssertTrue(editor.canSaveCustom)
        editor.saveCustomToPalette()
        XCTAssertEqual(editor.savedThemes.count, 1)
        XCTAssertFalse(editor.canSaveCustom, "те же цвета повторно не сохраняются")
        XCTAssertEqual(me.savedThemeCodes, editor.savedThemes, "палитра хранится в профиле")

        // Новая сессия редактора видит сохранённые цвета и может применить их.
        let again = deps.makeEditorViewModel(collection: nil)
        let code = try XCTUnwrap(again.savedThemes.first)
        again.select(CollectionTheme.all[5])
        again.useSaved(code)
        XCTAssertEqual(again.themeID, CollectionTheme.customPrefix + code)

        again.removeSaved(code)
        XCTAssertTrue(again.savedThemes.isEmpty)
        XCTAssertTrue(me.savedThemeCodes.isEmpty)
    }

    func testSavedPaletteLimitAndInvalidCodes() throws {
        let me = try signUp("ozzy")
        let many = (0..<20).map { String(format: "%06X-%06X", $0 * 1000 + 1, $0 * 2000 + 5) }
        try deps.session.setSavedThemes(many + ["nonsense", many[0]])
        XCTAssertEqual(me.savedThemeCodes.count, CollectionRules.savedThemesLimit)
        XCTAssertFalse(me.savedThemeCodes.contains("nonsense"))
        XCTAssertEqual(Set(me.savedThemeCodes).count, me.savedThemeCodes.count)
    }

    // MARK: Счётчик сохранений

    func testSaveCountCountsAllSavers() throws {
        let owner = try signUp("pip")
        let c = try makeCollections(1, for: owner)[0]
        let model = deps.makeProfileViewModel(user: owner)
        XCTAssertEqual(model.saveCount(of: c), 0)
        for name in ["quo1", "quo2", "quo3"] {
            let user = try signUp(name)
            try deps.social.setSaved(true, c, as: user)
        }
        XCTAssertEqual(model.saveCount(of: c), 3)
        try deps.social.setSaved(false, c, as: deps.session.currentUser!)
        XCTAssertEqual(model.saveCount(of: c), 2)
        XCTAssertEqual(savesText(0), "0 saves")
        XCTAssertEqual(savesText(1), "1 save")
        XCTAssertEqual(savesText(2), "2 saves")
    }
}
