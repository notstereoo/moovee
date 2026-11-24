import CommonCrypto
import Foundation
import SwiftData

enum AuthError: LocalizedError, Equatable {
    case invalidUsername, weakPassword, usernameTaken, invalidCredentials, storage
    /// Слишком много неудачных попыток входа; повторить можно через `retryAfter` секунд.
    case tooManyAttempts(retryAfter: Int)

    var errorDescription: String? {
        switch self {
        case .invalidUsername: String(localized: "Имя пользователя: 3–20 символов, латинские буквы, цифры и «_».")
        case .weakPassword: String(localized: "Пароль должен содержать не менее 8 символов.")
        case .usernameTaken: String(localized: "Это имя уже занято. Выберите другое.")
        case .invalidCredentials: String(localized: "Неверное имя пользователя или пароль.")
        case .storage: String(localized: "Не удалось сохранить данные на устройстве. Повторите попытку.")
        case .tooManyAttempts(let seconds):
            seconds >= 60
                ? String(localized: "Слишком много попыток. Повторите через \((seconds + 59) / 60) мин.")
                : String(localized: "Слишком много попыток. Повторите через \(seconds) с.")
        }
    }
}

/// PBKDF2-HMAC-SHA256 с индивидуальной солью.
enum PasswordHasher {
    static func randomSalt() -> Data { Data((0..<16).map { _ in UInt8.random(in: 0...255) }) }

    static func hash(_ password: String, salt: Data, rounds: UInt32 = 120_000) -> Data {
        let keyLength = 32
        var key = [UInt8](repeating: 0, count: keyLength)
        let status = salt.withUnsafeBytes { (saltBuf: UnsafeRawBufferPointer) -> Int32 in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2), password, password.utf8.count,
                saltBuf.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                &key, keyLength)
        }
        precondition(status == Int32(kCCSuccess), "PBKDF2 failed")
        return Data(key)
    }

    static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) { diff |= x ^ y }
        return diff == 0
    }
}

/// Локальные аккаунты: профиль — в SwiftData, секреты входа (соль и хэш пароля) — только в `SecretStore`.
@MainActor
struct LocalAuthProvider: AuthProvider {
    let context: ModelContext
    let secrets: any SecretStore
    private let throttle: LoginThrottle
    /// Хэш для сравнения, когда пользователя нет: время ответа не выдаёт, существует ли имя.
    private static let dummyCredentials = (salt: Data(repeating: 7, count: 16), hash: Data(repeating: 9, count: 32))

    init(context: ModelContext, secrets: any SecretStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.context = context
        self.secrets = secrets
        self.throttle = LoginThrottle(secrets: secrets, now: now)
    }

    static func isValid(username: String) -> Bool {
        username.range(of: "^[a-z0-9_]{3,20}$", options: .regularExpression) != nil
    }

    // MARK: Секреты

    private static func credentialsKey(_ id: UUID) -> String { "credentials.\(id.uuidString)" }

    private func storeCredentials(salt: Data, hash: Data, for id: UUID) throws {
        do { try secrets.set(salt + hash, for: Self.credentialsKey(id)) } catch { throw AuthError.storage }
    }

    private func credentials(for id: UUID) -> (salt: Data, hash: Data)? {
        guard let blob = secrets.data(for: Self.credentialsKey(id)), blob.count == 48 else { return nil }
        return (Data(blob.prefix(16)), Data(blob.suffix(32)))
    }

    /// Переносит пароли из старых версий (хэш лежал в SwiftData) в защищённое хранилище.
    func migrateLegacyCredentials() {
        let users = (try? context.fetch(FetchDescriptor<UserAccount>())) ?? []
        var changed = false
        for user in users {
            guard let hash = user.passwordHash, let salt = user.salt else { continue }
            if credentials(for: user.id) == nil {
                guard (try? storeCredentials(salt: salt, hash: hash, for: user.id)) != nil else { continue }
            }
            user.passwordHash = nil
            user.salt = nil
            changed = true
        }
        if changed { try? context.save() }
    }

    // MARK: AuthProvider

    func register(username raw: String, password: String) throws -> UserAccount {
        let name = Self.normalized(raw)
        guard Self.isValid(username: name) else { throw AuthError.invalidUsername }
        guard password.count >= 8 else { throw AuthError.weakPassword }
        guard try findUser(named: name) == nil else { throw AuthError.usernameTaken }

        let salt = PasswordHasher.randomSalt()
        let user = UserAccount(username: name)
        try storeCredentials(salt: salt, hash: PasswordHasher.hash(password, salt: salt), for: user.id)
        context.insert(user)
        do { try context.save() } catch {
            context.rollback()
            secrets.remove(Self.credentialsKey(user.id))
            throw AuthError.storage
        }
        return user
    }

    func login(username raw: String, password: String) throws -> UserAccount {
        let name = Self.normalized(raw)
        try ensureNotLocked(name)
        let user = try findUser(named: name)
        let verified = user.map { !$0.isDemo && verify(password, for: $0) } ?? dummyVerify(password)
        guard verified, let user else {
            throttle.recordFailure(for: name)
            throw AuthError.invalidCredentials
        }
        throttle.reset(for: name)
        return user
    }

    func user(id: UUID) -> UserAccount? {
        let descriptor = FetchDescriptor<UserAccount>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    func updateBio(_ bio: String, for user: UserAccount) throws {
        user.bio = String(bio.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        try save()
    }

    func setProfilePrivate(_ isPrivate: Bool, for user: UserAccount) throws {
        user.isProfilePrivate = isPrivate
        try save()
    }

    /// Удаляет аккаунт и все его данные (подборки, отзывы, любимые) после подтверждения паролем.
    func deleteAccount(_ user: UserAccount, password: String) throws {
        let name = user.username
        try ensureNotLocked(name)
        guard !user.isDemo, verify(password, for: user) else {
            throttle.recordFailure(for: name)
            throw AuthError.invalidCredentials
        }
        let id = user.id
        context.delete(user)
        do { try context.save() } catch {
            context.rollback()
            throw AuthError.storage
        }
        secrets.remove(Self.credentialsKey(id))
        throttle.reset(for: name)
    }

    // MARK: Внутреннее

    private func ensureNotLocked(_ name: String) throws {
        let wait = throttle.lockRemaining(for: name)
        if wait > 0 { throw AuthError.tooManyAttempts(retryAfter: Int(wait.rounded(.up))) }
    }

    private func verify(_ password: String, for user: UserAccount) -> Bool {
        guard let stored = credentials(for: user.id) else {
            dummyVerify(password)
            return false
        }
        return PasswordHasher.constantTimeEqual(stored.hash, PasswordHasher.hash(password, salt: stored.salt))
    }

    @discardableResult
    private func dummyVerify(_ password: String) -> Bool {
        _ = PasswordHasher.hash(password, salt: Self.dummyCredentials.salt)
        return false
    }

    private func save() throws {
        do { try context.save() } catch {
            context.rollback()
            throw AuthError.storage
        }
    }

    private static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func findUser(named name: String) throws -> UserAccount? {
        do {
            let descriptor = FetchDescriptor<UserAccount>(predicate: #Predicate { $0.username == name })
            return try context.fetch(descriptor).first
        } catch { throw AuthError.storage }
    }
}

/// Текущая сессия: кто вошёл. Идентификатор сессии хранится в `SecretStore` (Keychain), а не в `UserDefaults`.
@MainActor @Observable
final class AppSession {
    private(set) var currentUser: UserAccount?
    @ObservationIgnored private let auth: any AuthProvider
    @ObservationIgnored private let secrets: any SecretStore
    private static let sessionKey = "session.userID"
    private static let legacyDefaultsKey = "session.userID"

    /// `legacyDefaults` — откуда забрать сессию, сохранённую старой версией (и удалить оттуда).
    init(auth: any AuthProvider, secrets: any SecretStore, legacyDefaults: UserDefaults? = nil) {
        self.auth = auth
        self.secrets = secrets
        if let legacy = legacyDefaults?.string(forKey: Self.legacyDefaultsKey) {
            if secrets.data(for: Self.sessionKey) == nil { try? secrets.set(Data(legacy.utf8), for: Self.sessionKey) }
            legacyDefaults?.removeObject(forKey: Self.legacyDefaultsKey)
        }
        restore()
    }

    func register(username: String, password: String) throws {
        try start(auth.register(username: username, password: password))
    }

    func login(username: String, password: String) throws {
        try start(auth.login(username: username, password: password))
    }

    func logout() {
        secrets.remove(Self.sessionKey)
        currentUser = nil
    }

    func updateBio(_ bio: String) throws {
        guard let user = currentUser else { return }
        try auth.updateBio(bio, for: user)
    }

    func setProfilePrivate(_ isPrivate: Bool) throws {
        guard let user = currentUser else { return }
        try auth.setProfilePrivate(isPrivate, for: user)
    }

    /// Необратимо удаляет аккаунт и все данные пользователя, затем выходит.
    func deleteAccount(password: String) throws {
        guard let user = currentUser else { return }
        try auth.deleteAccount(user, password: password)
        logout()
    }

    private func start(_ user: UserAccount) throws {
        do { try secrets.set(Data(user.id.uuidString.utf8), for: Self.sessionKey) } catch { throw AuthError.storage }
        currentUser = user
    }

    private func restore() {
        guard let data = secrets.data(for: Self.sessionKey),
            let raw = String(data: data, encoding: .utf8), let id = UUID(uuidString: raw)
        else { return }
        currentUser = auth.user(id: id)
        if currentUser == nil { secrets.remove(Self.sessionKey) }
    }
}
