import SwiftData
import XCTest

@testable import CineBoard

/// Часы для проверки блокировок по времени.
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date = date.addingTimeInterval(seconds) } }
}

@MainActor
final class SecurityTests: XCTestCase {
    private var container: ModelContainer!
    private var secrets: InMemorySecretStore!
    private var clock: Clock!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try AppSchema.makeContainer(inMemory: true)
        secrets = InMemorySecretStore()
        clock = Clock()
    }

    private func makeAuth() -> LocalAuthProvider {
        LocalAuthProvider(context: context, secrets: secrets, now: { [clock] in clock!.now })
    }

    private func makeSession(auth: LocalAuthProvider? = nil) -> AppSession {
        AppSession(auth: auth ?? makeAuth(), secrets: secrets)
    }

    private func movie(_ id: Int) -> Movie {
        Movie(
            id: id, title: "Фильм \(id)", overview: nil, posterPath: nil, backdropPath: nil,
            releaseDate: "2020-01-01", voteAverage: nil, runtime: nil, genres: nil)
    }

    // MARK: Секреты не в базе

    func testPasswordHashIsNotStoredInDatabase() throws {
        let user = try makeAuth().register(username: "alice", password: "password1")
        XCTAssertNil(user.passwordHash)
        XCTAssertNil(user.salt)
        XCTAssertTrue(secrets.keys.contains("credentials.\(user.id.uuidString)"))
        // Пароль в открытом виде нигде не лежит.
        for key in secrets.keys {
            let blob = secrets.data(for: key)!
            XCTAssertNil(blob.range(of: Data("password1".utf8)), key)
        }
    }

    func testLoginUsesKeychainCredentials() throws {
        let auth = makeAuth()
        _ = try auth.register(username: "bob_1", password: "password1")
        XCTAssertNoThrow(try auth.login(username: "BOB_1", password: "password1"))
        XCTAssertThrowsError(try auth.login(username: "bob_1", password: "password2")) {
            XCTAssertEqual($0 as? AuthError, .invalidCredentials)
        }
    }

    func testRegisterFailsCleanlyWhenSecretStoreFails() throws {
        secrets.failsOnWrite = true
        XCTAssertThrowsError(try makeAuth().register(username: "carol", password: "password1")) {
            XCTAssertEqual($0 as? AuthError, .storage)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserAccount>()), 0)  // аккаунт-«сирота» не создан
    }

    func testLegacyCredentialsMigrateToSecretStore() throws {
        // Старая версия хранила хэш прямо в SwiftData.
        let salt = PasswordHasher.randomSalt()
        let legacy = UserAccount(
            username: "olduser", passwordHash: PasswordHasher.hash("oldpassword", salt: salt), salt: salt)
        context.insert(legacy)
        try context.save()

        let auth = makeAuth()
        auth.migrateLegacyCredentials()
        XCTAssertNil(legacy.passwordHash)
        XCTAssertNil(legacy.salt)
        XCTAssertNoThrow(try auth.login(username: "olduser", password: "oldpassword"))
        XCTAssertThrowsError(try auth.login(username: "olduser", password: "nope-nope"))

        auth.migrateLegacyCredentials()  // повторный запуск безопасен
        XCTAssertNoThrow(try auth.login(username: "olduser", password: "oldpassword"))
    }

    // MARK: Сессия

    func testSessionLivesInSecretStoreAndSurvivesRelaunch() throws {
        let first = makeSession()
        try first.register(username: "dave", password: "password1")
        XCTAssertNotNil(secrets.data(for: "session.userID"))

        XCTAssertEqual(makeSession().currentUser?.username, "dave")
        first.logout()
        XCTAssertNil(secrets.data(for: "session.userID"))
        XCTAssertNil(makeSession().currentUser)
    }

    func testLegacySessionMovesFromUserDefaults() throws {
        let user = try makeAuth().register(username: "erin", password: "password1")
        let suite = "legacy-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(user.id.uuidString, forKey: "session.userID")

        let session = AppSession(auth: makeAuth(), secrets: secrets, legacyDefaults: defaults)
        XCTAssertEqual(session.currentUser?.username, "erin")
        XCTAssertNil(defaults.string(forKey: "session.userID"), "из UserDefaults сессия должна исчезнуть")
        XCTAssertNotNil(secrets.data(for: "session.userID"))
        defaults.removePersistentDomain(forName: suite)
    }

    func testStaleSessionIsDropped() throws {
        try secrets.set(Data(UUID().uuidString.utf8), for: "session.userID")
        XCTAssertNil(makeSession().currentUser)
        XCTAssertNil(secrets.data(for: "session.userID"))
    }

    // MARK: Блокировка подбора пароля

    func testThrottleLocksAfterFiveFailures() throws {
        let auth = makeAuth()
        _ = try auth.register(username: "frank", password: "password1")

        for _ in 0..<LoginThrottle.freeAttempts {
            XCTAssertThrowsError(try auth.login(username: "frank", password: "wrong-pass")) {
                XCTAssertEqual($0 as? AuthError, .invalidCredentials)
            }
        }
        // Даже верный пароль сейчас не принимается.
        XCTAssertThrowsError(try auth.login(username: "frank", password: "password1")) {
            XCTAssertEqual($0 as? AuthError, .tooManyAttempts(retryAfter: 30))
        }
        clock.advance(31)
        XCTAssertNoThrow(try auth.login(username: "frank", password: "password1"))
    }

    func testThrottleDelayGrowsAndIsCapped() {
        XCTAssertEqual(LoginThrottle.delay(afterFailures: 4), 0)
        XCTAssertEqual(LoginThrottle.delay(afterFailures: 5), 30)
        XCTAssertEqual(LoginThrottle.delay(afterFailures: 6), 60)
        XCTAssertEqual(LoginThrottle.delay(afterFailures: 7), 120)
        XCTAssertEqual(LoginThrottle.delay(afterFailures: 50), LoginThrottle.maxDelay)
    }

    func testThrottleSurvivesRelaunchAndAppliesToUnknownUsers() throws {
        let auth = makeAuth()
        for _ in 0..<LoginThrottle.freeAttempts {
            XCTAssertThrowsError(try auth.login(username: "ghost", password: "whatever1"))
        }
        // «Перезапуск»: новый провайдер с тем же хранилищем. Несуществующее имя блокируется так же.
        XCTAssertThrowsError(try makeAuth().login(username: "ghost", password: "whatever1")) {
            guard case .tooManyAttempts = $0 as? AuthError else { return XCTFail("expected lock, got \($0)") }
        }
    }

    func testSuccessfulLoginResetsCounter() throws {
        let auth = makeAuth()
        _ = try auth.register(username: "gina", password: "password1")
        for _ in 0..<(LoginThrottle.freeAttempts - 1) {
            XCTAssertThrowsError(try auth.login(username: "gina", password: "bad-bad-bad"))
        }
        XCTAssertNoThrow(try auth.login(username: "gina", password: "password1"))
        for _ in 0..<(LoginThrottle.freeAttempts - 1) {
            XCTAssertThrowsError(try auth.login(username: "gina", password: "bad-bad-bad")) {
                XCTAssertEqual($0 as? AuthError, .invalidCredentials)  // блокировки нет: счётчик сброшен
            }
        }
    }

    // MARK: Удаление аккаунта

    func testDeleteAccountRemovesEverything() throws {
        let deps = AppDependencies.local(context: context, secrets: secrets)
        try deps.session.register(username: "henry", password: "password1")
        let me = deps.session.currentUser!
        let id = me.id
        let c = try deps.collections.create(title: "A", details: "", isPublic: true, as: me)
        try deps.collections.add(movie(1), to: c, as: me)
        _ = try deps.reviews.save(movie: movie(1), rating: 7, text: "ок", as: me)
        try deps.favorites.add(movie(1), as: me)

        // Неверный пароль — ничего не удаляется.
        XCTAssertThrowsError(try deps.session.deleteAccount(password: "wrong-pass")) {
            XCTAssertEqual($0 as? AuthError, .invalidCredentials)
        }
        XCTAssertNotNil(deps.session.currentUser)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserAccount>()), 1)

        try deps.session.deleteAccount(password: "password1")
        XCTAssertNil(deps.session.currentUser)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserAccount>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MovieCollection>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectionItem>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Review>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FavoriteMovie>()), 0)
        XCTAssertNil(secrets.data(for: "credentials.\(id.uuidString)"))
        XCTAssertNil(secrets.data(for: "session.userID"))

        // Имя снова свободно.
        XCTAssertNoThrow(try deps.session.register(username: "henry", password: "password1"))
    }

    func testDeleteAccountIsThrottled() throws {
        let deps = AppDependencies.local(context: context, secrets: secrets)
        try deps.session.register(username: "ivy", password: "password1")
        for _ in 0..<LoginThrottle.freeAttempts {
            XCTAssertThrowsError(try deps.session.deleteAccount(password: "wrong-pass"))
        }
        XCTAssertThrowsError(try deps.session.deleteAccount(password: "password1")) {
            guard case .tooManyAttempts = $0 as? AuthError else { return XCTFail("expected lock, got \($0)") }
        }
        XCTAssertNotNil(deps.session.currentUser)
    }

    // MARK: Закрытый профиль

    func testPrivateProfileHidesContentFromOthers() throws {
        let deps = AppDependencies.local(context: context, secrets: secrets)
        try deps.session.register(username: "jack", password: "password1")
        let jack = deps.session.currentUser!
        let open = try deps.collections.create(title: "Открытая", details: "", isPublic: true, as: jack)
        try deps.favorites.add(movie(1), as: jack)
        _ = try deps.reviews.save(movie: movie(1), rating: 8, text: "", as: jack)
        try deps.session.setProfilePrivate(true)

        // Владелец по-прежнему видит всё.
        let own = deps.makeProfileViewModel(user: jack)
        XCTAssertFalse(own.isContentHidden)
        XCTAssertEqual(own.collections.count, 1)
        XCTAssertEqual(own.favorites.count, 1)

        try deps.session.register(username: "kim", password: "password1")
        let visitor = deps.makeProfileViewModel(user: jack)
        XCTAssertTrue(visitor.isContentHidden)
        XCTAssertTrue(visitor.collections.isEmpty)
        XCTAssertTrue(visitor.favorites.isEmpty)
        XCTAssertTrue(visitor.reviews.isEmpty)
        XCTAssertFalse(open.isVisible(to: deps.session.currentUser), "прямой доступ к публичной подборке закрыт")
        XCTAssertTrue(deps.collections.publicCollections(excluding: deps.session.currentUser).isEmpty)
        XCTAssertEqual(deps.makeCollectionDetailViewModel(open).availability, .privateToViewer)

        // Снова открываем профиль — всё возвращается.
        try deps.session.login(username: "jack", password: "password1")
        try deps.session.setProfilePrivate(false)
        try deps.session.login(username: "kim", password: "password1")
        XCTAssertFalse(deps.makeProfileViewModel(user: jack).isContentHidden)
        XCTAssertEqual(deps.collections.publicCollections(excluding: deps.session.currentUser).count, 1)
    }

    // MARK: Keychain (реальный)

    func testKeychainStoreRoundTrip() throws {
        let store = KeychainSecretStore(service: "cineboard.tests.\(UUID().uuidString)")
        defer { store.remove("k") }
        XCTAssertNil(store.data(for: "k"))
        try store.set(Data("one".utf8), for: "k")
        XCTAssertEqual(store.data(for: "k"), Data("one".utf8))
        try store.set(Data("two".utf8), for: "k")  // обновление
        XCTAssertEqual(store.data(for: "k"), Data("two".utf8))
        store.remove("k")
        XCTAssertNil(store.data(for: "k"))
    }
}
