import SwiftData
import UIKit
import XCTest

@testable import CineBoard

@MainActor
final class ProfileSocialTests: XCTestCase {
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

    private func login(_ name: String) throws {
        try deps.session.login(username: name, password: "password1")
    }

    private func movie(_ id: Int) -> Movie {
        Movie(
            id: id, title: "Movie \(id)", overview: nil, posterPath: nil, backdropPath: nil, releaseDate: "2020-01-01",
            voteAverage: nil, runtime: nil, genres: nil)
    }

    private func imageData(width: Int, height: Int, color: UIColor = .red) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.pngData { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    // MARK: Имя, аватар, баннер

    func testShownNameFallsBackToUsername() throws {
        let me = try signUp("zed")
        XCTAssertEqual(me.shownName, "zed")
        try deps.session.updateProfile(ProfileEdit(displayName: "  Zed Zed  ", bio: "", isPrivate: false))
        XCTAssertEqual(me.shownName, "Zed Zed")
        try deps.session.updateProfile(ProfileEdit(displayName: "   ", bio: "", isPrivate: false))
        XCTAssertEqual(me.shownName, "zed")
    }

    func testDisplayNamesCanRepeatButUsernamesCannot() throws {
        let a = try signUp("alpha")
        try deps.session.updateProfile(ProfileEdit(displayName: "Sam", bio: "", isPrivate: false))
        let b = try signUp("bravo")
        try deps.session.updateProfile(ProfileEdit(displayName: "Sam", bio: "", isPrivate: false))
        XCTAssertEqual(a.shownName, b.shownName)
        XCTAssertThrowsError(try deps.session.register(username: "alpha", password: "password1")) {
            XCTAssertEqual($0 as? AuthError, .usernameTaken)
        }
    }

    func testProfileEditLimitsAndImageChanges() throws {
        let me = try signUp("carol")
        let longName = String(repeating: "n", count: 100)
        let longBio = String(repeating: "b", count: 400)
        let avatar = Data([1, 2, 3])
        try deps.session.updateProfile(
            ProfileEdit(displayName: longName, bio: longBio, isPrivate: true, avatar: .set(avatar), banner: .keep))
        XCTAssertEqual(me.displayName.count, ProfileRules.maxNameLength)
        XCTAssertEqual(me.bio.count, ProfileRules.maxBioLength)
        XCTAssertTrue(me.isProfilePrivate)
        XCTAssertEqual(me.avatarData, avatar)
        XCTAssertNil(me.bannerData)

        try deps.session.updateProfile(ProfileEdit(displayName: "", bio: "", isPrivate: false, avatar: .keep))
        XCTAssertEqual(me.avatarData, avatar, ".keep не должен менять фото")
        try deps.session.updateProfile(ProfileEdit(displayName: "", bio: "", isPrivate: false, avatar: .remove))
        XCTAssertNil(me.avatarData)
    }

    func testImageProcessingCropsAndCompresses() throws {
        let avatar = try XCTUnwrap(ImageProcessing.avatarJPEG(from: imageData(width: 2000, height: 1000)))
        let avatarImage = try XCTUnwrap(UIImage(data: avatar))
        XCTAssertEqual(avatarImage.size.width * avatarImage.scale, 512, accuracy: 1)
        XCTAssertEqual(avatarImage.size.height * avatarImage.scale, 512, accuracy: 1)

        let banner = try XCTUnwrap(ImageProcessing.bannerJPEG(from: imageData(width: 800, height: 1600)))
        let bannerImage = try XCTUnwrap(UIImage(data: banner))
        XCTAssertEqual(bannerImage.size.width / bannerImage.size.height, 2, accuracy: 0.01)

        XCTAssertNil(ImageProcessing.avatarJPEG(from: Data([0, 1, 2])), "не изображение")
    }

    func testProfileEditorViewModel() throws {
        let me = try signUp("dina")
        let editor = deps.makeProfileEditorViewModel()
        XCTAssertEqual(editor.username, "dina")
        XCTAssertFalse(editor.hasAvatar)
        XCTAssertTrue(editor.setAvatar(from: imageData(width: 300, height: 300)))
        XCTAssertTrue(editor.setBanner(from: imageData(width: 900, height: 300)))
        XCTAssertFalse(editor.setAvatar(from: Data([9, 9])))
        XCTAssertNotNil(editor.errorMessage)
        editor.errorMessage = nil
        editor.displayName = "Dina D."
        editor.bio = "hello"
        XCTAssertTrue(editor.canSave)
        XCTAssertTrue(editor.save())
        XCTAssertEqual(me.shownName, "Dina D.")
        XCTAssertNotNil(me.avatarData)
        XCTAssertNotNil(me.bannerData)

        let again = deps.makeProfileEditorViewModel()
        XCTAssertTrue(again.hasAvatar)
        again.removeAvatar()
        XCTAssertFalse(again.hasAvatar)
        XCTAssertTrue(again.save())
        XCTAssertNil(me.avatarData)
        XCTAssertNotNil(me.bannerData)

        again.displayName = String(repeating: "x", count: ProfileRules.maxNameLength + 1)
        XCTAssertFalse(again.canSave)
    }

    // MARK: Подписки

    func testFollowUnfollowCountsAndFriends() throws {
        let a = try signUp("ann")
        let b = try signUp("ben")
        let c = try signUp("cat")
        let social = deps.social

        try social.follow(b, as: a)
        try social.follow(b, as: a)  // повтор — без эффекта
        try social.follow(b, as: c)
        XCTAssertTrue(social.isFollowing(a, b))
        XCTAssertFalse(social.isFollowing(b, a))
        XCTAssertFalse(social.areFriends(a, b))
        XCTAssertEqual(social.followersCount(of: b), 2)
        XCTAssertEqual(social.followingCount(of: a), 1)
        XCTAssertEqual(Set(social.followers(of: b).map(\.username)), ["ann", "cat"])

        try social.follow(a, as: b)  // взаимно → друзья
        XCTAssertTrue(social.areFriends(a, b))
        XCTAssertTrue(social.areFriends(b, a))

        try social.unfollow(b, as: a)
        XCTAssertFalse(social.areFriends(a, b))
        XCTAssertEqual(social.followersCount(of: b), 1)
        XCTAssertNoThrow(try social.unfollow(b, as: a))  // повторная отписка безопасна
    }

    func testCannotFollowSelf() throws {
        let a = try signUp("dan")
        XCTAssertThrowsError(try deps.social.follow(a, as: a)) {
            XCTAssertEqual($0 as? SocialError, .cannotFollowSelf)
        }
        XCTAssertEqual(deps.social.followingCount(of: a), 0)
    }

    func testProfileViewModelFollowFlow() throws {
        let target = try signUp("eve")
        _ = try signUp("finn")
        let model = deps.makeProfileViewModel(user: target)
        XCTAssertFalse(model.isMe)
        XCTAssertTrue(model.canFollow)
        XCTAssertFalse(model.isFollowing)
        model.toggleFollow()
        XCTAssertTrue(model.isFollowing)
        XCTAssertEqual(model.followersCount, 1)
        XCTAssertFalse(model.isFriend)

        try login("eve")
        deps.makeProfileViewModel(user: deps.session.currentUser!).toggleFollow()  // на себя нельзя — без эффекта
        XCTAssertEqual(deps.social.followingCount(of: target), 0)
        let finn = try XCTUnwrap(deps.social.followers(of: target).first)
        deps.makeProfileViewModel(user: finn).toggleFollow()
        XCTAssertTrue(deps.makeProfileViewModel(user: finn).isFriend)
        XCTAssertTrue(deps.makeProfileViewModel(user: finn).isFollowing)
    }

    func testFollowListViewModel() throws {
        let a = try signUp("gus")
        let b = try signUp("hal")
        try deps.social.follow(a, as: b)
        XCTAssertEqual(deps.makeFollowListViewModel(user: a, kind: .followers).users.map(\.username), ["hal"])
        XCTAssertEqual(deps.makeFollowListViewModel(user: b, kind: .following).users.map(\.username), ["gus"])
        XCTAssertTrue(deps.makeFollowListViewModel(user: a, kind: .following).users.isEmpty)
    }

    // MARK: Лайки

    func testLikesToggleAndTotals() throws {
        let owner = try signUp("ivy")
        let c1 = try deps.collections.create(title: "One", details: "", isPublic: true, as: owner)
        let c2 = try deps.collections.create(title: "Two", details: "", isPublic: true, as: owner)
        let fan1 = try signUp("jon")
        let fan2 = try signUp("kay")

        try deps.social.setLiked(true, c1, as: fan2)
        try deps.social.setLiked(true, c1, as: fan2)  // идемпотентно
        try deps.social.setLiked(true, c2, as: fan2)
        try deps.social.setLiked(true, c1, as: fan1)
        XCTAssertEqual(deps.social.likeCount(of: c1), 2)
        XCTAssertEqual(deps.social.totalLikes(ofOwner: owner), 3)
        XCTAssertTrue(deps.social.isLiked(c1, by: fan1))

        try deps.social.setLiked(false, c1, as: fan1)
        XCTAssertFalse(deps.social.isLiked(c1, by: fan1))
        XCTAssertEqual(deps.social.totalLikes(ofOwner: owner), 2)
        XCTAssertNoThrow(try deps.social.setLiked(false, c1, as: fan1))
    }

    func testCannotLikeOwnOrHiddenCollections() throws {
        let owner = try signUp("lee")
        let own = try deps.collections.create(title: "Mine", details: "", isPublic: true, as: owner)
        let secret = try deps.collections.create(title: "Secret", details: "", isPublic: false, as: owner)
        XCTAssertThrowsError(try deps.social.setLiked(true, own, as: owner)) {
            XCTAssertEqual($0 as? SocialError, .cannotLikeOwn)
        }
        let other = try signUp("mia")
        XCTAssertThrowsError(try deps.social.setLiked(true, secret, as: other)) {
            XCTAssertEqual($0 as? SocialError, .collectionUnavailable)
        }
        XCTAssertThrowsError(try deps.social.setSaved(true, secret, as: other)) {
            XCTAssertEqual($0 as? SocialError, .collectionUnavailable)
        }
        XCTAssertEqual(deps.social.totalLikes(ofOwner: owner), 0)
    }

    // MARK: Сохранённые подборки

    func testSaveCollectionsAndListInProfile() throws {
        let owner = try signUp("ned")
        let c1 = try deps.collections.create(title: "First", details: "d1", isPublic: true, as: owner)
        let c2 = try deps.collections.create(title: "Second", details: "", isPublic: true, as: owner)
        let me = try signUp("ola")

        XCTAssertThrowsError(try deps.social.setSaved(true, c1, as: owner)) {  // владелец — не себе
            XCTAssertEqual($0 as? SocialError, .cannotSaveOwn)
        }
        try deps.social.setSaved(true, c1, as: me)
        try deps.social.setSaved(true, c2, as: me)
        try deps.social.setSaved(true, c2, as: me)
        XCTAssertEqual(deps.social.savedCollections(of: me).map(\.title), ["Second", "First"])  // новые сверху
        XCTAssertTrue(deps.social.isSaved(c1, by: me))

        // Видит свои сохранённые только владелец профиля.
        let own = deps.makeProfileViewModel(user: me)
        XCTAssertEqual(own.savedCollections.count, 2)
        try login("ned")
        XCTAssertTrue(deps.makeProfileViewModel(user: me).savedCollections.isEmpty)

        try login("ola")
        try deps.social.setSaved(false, c1, as: me)
        XCTAssertEqual(deps.social.savedCollections(of: me).map(\.title), ["Second"])
    }

    func testSavedCollectionDisappearsWhenMadePrivateOrDeleted() throws {
        let owner = try signUp("pat")
        let c = try deps.collections.create(title: "Shared", details: "", isPublic: true, as: owner)
        let me = try signUp("quin")
        try deps.social.setSaved(true, c, as: me)
        try deps.social.setLiked(true, c, as: me)

        try deps.collections.update(c, title: "Shared", details: "", isPublic: false, as: owner)
        XCTAssertTrue(deps.social.savedCollections(of: me).isEmpty, "приватную подборку чужого не показываем")
        try deps.collections.update(c, title: "Shared", details: "", isPublic: true, as: owner)
        XCTAssertEqual(deps.social.savedCollections(of: me).count, 1)

        try deps.collections.delete(c, as: owner)
        XCTAssertTrue(deps.social.savedCollections(of: me).isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SavedCollection>()), 0, "связи удалённой подборки убраны")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectionLike>()), 0)
    }

    func testCollectionDetailViewModelLikeAndSave() throws {
        let owner = try signUp("ray")
        let c = try deps.collections.create(title: "Mix", details: "", isPublic: true, as: owner)
        let ownerModel = deps.makeCollectionDetailViewModel(c)
        XCTAssertFalse(ownerModel.canInteract)

        _ = try signUp("sue")
        let model = deps.makeCollectionDetailViewModel(c)
        XCTAssertTrue(model.canInteract)
        XCTAssertEqual(model.likeCount, 0)
        model.toggleLike()
        model.toggleSave()
        XCTAssertTrue(model.isLiked)
        XCTAssertTrue(model.isSaved)
        XCTAssertEqual(model.likeCount, 1)
        XCTAssertEqual(ownerModel.likeCount, 1, "владелец видит число лайков")
        model.toggleLike()
        model.toggleSave()
        XCTAssertFalse(model.isLiked)
        XCTAssertFalse(model.isSaved)
        XCTAssertNil(model.errorMessage)
    }

    func testProfileViewModelTotalLikesAndPrivateProfile() throws {
        let owner = try signUp("tim")
        let c = try deps.collections.create(title: "Hits", details: "", isPublic: true, as: owner)
        let fan = try signUp("uma")
        try deps.social.setLiked(true, c, as: fan)

        let model = deps.makeProfileViewModel(user: owner)
        XCTAssertEqual(model.totalLikes, 1)
        XCTAssertFalse(model.isContentHidden)

        try login("tim")
        try deps.session.updateProfile(ProfileEdit(displayName: "", bio: "", isPrivate: true))
        try login("uma")
        XCTAssertTrue(model.isContentHidden)
        XCTAssertTrue(model.collections.isEmpty)
        XCTAssertEqual(model.followersCount, 0)  // счётчики остаются доступными
        XCTAssertTrue(deps.social.savedCollections(of: fan).isEmpty)
        XCTAssertThrowsError(try deps.social.setSaved(true, c, as: fan)) {
            XCTAssertEqual($0 as? SocialError, .collectionUnavailable)
        }
    }

    // MARK: Удаление аккаунта

    func testDeleteAccountRemovesSocialLinks() throws {
        let doomed = try signUp("vic")
        let c = try deps.collections.create(title: "Mine", details: "", isPublic: true, as: doomed)
        let friend = try signUp("wes")
        let fc = try deps.collections.create(title: "Theirs", details: "", isPublic: true, as: friend)
        try deps.social.follow(doomed, as: friend)
        try deps.social.follow(friend, as: doomed)
        try deps.social.setLiked(true, c, as: friend)
        try deps.social.setSaved(true, c, as: friend)
        try deps.social.setLiked(true, fc, as: doomed)
        try deps.social.setSaved(true, fc, as: doomed)

        try login("vic")
        try deps.session.deleteAccount(password: "password1")

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Follow>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectionLike>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SavedCollection>()), 0)
        XCTAssertEqual(deps.social.followersCount(of: friend), 0)
        XCTAssertEqual(deps.social.totalLikes(ofOwner: friend), 0)
    }

    // MARK: Английский интерфейс

    func testEnglishPluralHelpers() {
        XCTAssertEqual(filmsText(0), "0 films")
        XCTAssertEqual(filmsText(1), "1 film")
        XCTAssertEqual(filmsText(2), "2 films")
        XCTAssertEqual(ratingsText(1), "1 rating")
        XCTAssertEqual(ratingsText(12), "12 ratings")
    }

    func testSortModesHaveEnglishTitles() {
        XCTAssertEqual(CollectionSort.added.title, "Newest first")
        XCTAssertEqual(CollectionSort.manual.title, "Author's order")
    }

    // MARK: Демо-данные

    func testDemoUsersHaveNamesAndConnections() throws {
        DemoSeeder.seedIfNeeded(context)
        DemoSeeder.seedIfNeeded(context)  // идемпотентно
        let users = try context.fetch(FetchDescriptor<UserAccount>())
        let anna = try XCTUnwrap(users.first { $0.username == "anna_films" })
        let max = try XCTUnwrap(users.first { $0.username == "max_cinema" })
        XCTAssertEqual(anna.shownName, "Anna Fields")
        XCTAssertTrue(deps.social.areFriends(anna, max))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Follow>()), 2)
        XCTAssertGreaterThan(deps.social.totalLikes(ofOwner: max), 0)
    }

    // MARK: Кадрирование

    func testCropGeometryCoversFrameAndClamps() {
        let g = CropGeometry(imageSize: CGSize(width: 2000, height: 1000), cropSize: CGSize(width: 400, height: 400))
        XCTAssertEqual(g.baseScale, 0.4, accuracy: 0.0001)  // высота определяет масштаб

        // По умолчанию — центр: квадрат 1000×1000 посередине.
        XCTAssertEqual(g.cropRect(zoom: 1, offset: .zero), CGRect(x: 500, y: 0, width: 1000, height: 1000))

        // Сдвиг фото вправо показывает его левую часть; за край выйти нельзя.
        XCTAssertEqual(g.cropRect(zoom: 1, offset: CGSize(width: 200, height: 0)).minX, 0, accuracy: 0.001)
        XCTAssertEqual(g.clampedOffset(CGSize(width: 999, height: 999), zoom: 1), CGSize(width: 200, height: 0))
        XCTAssertEqual(g.clampedOffset(CGSize(width: -999, height: -999), zoom: 1), CGSize(width: -200, height: 0))

        // Приближение уменьшает область и расширяет допустимый сдвиг.
        let zoomed = g.cropRect(zoom: 2, offset: .zero)
        XCTAssertEqual(zoomed.width, 500, accuracy: 0.001)
        XCTAssertEqual(g.clampedOffset(CGSize(width: 999, height: 999), zoom: 2), CGSize(width: 600, height: 200))
        XCTAssertEqual(g.clampedZoom(0.2), 1)
        XCTAssertEqual(g.clampedZoom(99), CropGeometry.maxZoom)

        // Область всегда внутри изображения.
        for zoom in [1, 1.5, 3, 5] as [CGFloat] {
            for off in [CGSize(width: -9999, height: -9999), CGSize(width: 9999, height: 9999), .zero] {
                let r = g.cropRect(zoom: zoom, offset: off)
                XCTAssertGreaterThanOrEqual(r.minX, -0.001)
                XCTAssertGreaterThanOrEqual(r.minY, -0.001)
                XCTAssertLessThanOrEqual(r.maxX, 2000.001)
                XCTAssertLessThanOrEqual(r.maxY, 1000.001)
            }
        }
    }

    func testCropPicksChosenRegion() throws {
        // Слева красная половина, справа синяя.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100), format: format).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
        }
        func centerColor(_ data: Data) throws -> (r: CGFloat, b: CGFloat) {
            let out = try XCTUnwrap(UIImage(data: data))
            XCTAssertEqual(out.size.width * out.scale, 64, accuracy: 1)
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
            let px = renderer.image { _ in out.draw(in: CGRect(x: -32, y: -32, width: 64, height: 64)) }
            let sample = try XCTUnwrap(px.cgImage?.dataProvider?.data as Data?)
            // Формат пикселей — BGRA.
            let b = CGFloat(sample[0]) / 255
            let r = CGFloat(sample[2]) / 255
            return (r, b)
        }
        let right = try XCTUnwrap(
            ImageProcessing.crop(image, rect: CGRect(x: 100, y: 0, width: 100, height: 100), outputSize: CGSize(width: 64, height: 64)))
        let left = try XCTUnwrap(
            ImageProcessing.crop(image, rect: CGRect(x: 0, y: 0, width: 100, height: 100), outputSize: CGSize(width: 64, height: 64)))
        let rightColor = try centerColor(right)
        let leftColor = try centerColor(left)
        XCTAssertGreaterThan(rightColor.b, 0.7)
        XCTAssertLessThan(rightColor.r, 0.3)
        XCTAssertGreaterThan(leftColor.r, 0.7)
        XCTAssertLessThan(leftColor.b, 0.3)
        XCTAssertNil(ImageProcessing.crop(image, rect: .zero, outputSize: CGSize(width: 10, height: 10)))
    }

    func testNormalizedImageLimitsSize() {
        let big = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 2000)).image { ctx in
            UIColor.green.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4000, height: 2000))
        }
        let normalized = ImageProcessing.normalized(big, maxSide: 1000)
        XCTAssertEqual(max(normalized.size.width, normalized.size.height) * normalized.scale, 1000, accuracy: 1)
        XCTAssertEqual(normalized.size.width / normalized.size.height, 2, accuracy: 0.01)
    }

    func testEditorAcceptsCroppedImages() throws {
        let me = try signUp("crop")
        let editor = deps.makeProfileEditorViewModel()
        let avatar = try XCTUnwrap(ImageProcessing.avatarJPEG(from: imageData(width: 400, height: 400)))
        let banner = try XCTUnwrap(ImageProcessing.bannerJPEG(from: imageData(width: 800, height: 400)))
        editor.applyAvatar(jpeg: avatar)
        editor.applyBanner(jpeg: banner)
        XCTAssertTrue(editor.hasAvatar && editor.hasBanner)
        XCTAssertTrue(editor.save())
        XCTAssertEqual(me.avatarData, avatar)
        XCTAssertEqual(me.bannerData, banner)
    }

    func testLikesText() {
        XCTAssertEqual(likesText(0), "0 likes")
        XCTAssertEqual(likesText(1), "1 like")
        XCTAssertEqual(likesText(7), "7 likes")
    }
}
