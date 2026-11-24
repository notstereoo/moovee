import Foundation
import SwiftData
import CommonCrypto

enum AuthError: LocalizedError, Equatable {
    case invalidUsername, weakPassword, usernameTaken, invalidCredentials, storage

    var errorDescription: String? {
        switch self {
        case .invalidUsername: "Имя пользователя: 3–20 символов, латинские буквы, цифры и «_»."
        case .weakPassword: "Пароль должен содержать не менее 8 символов."
        case .usernameTaken: "Это имя уже занято. Выберите другое."
        case .invalidCredentials: "Неверное имя пользователя или пароль."
        case .storage: "Не удалось сохранить данные на устройстве. Повторите попытку."
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

/// Локальные аккаунты в SwiftData (см. README → ограничения).
@MainActor
struct LocalAuthProvider: AuthProvider {
    let context: ModelContext

    static func isValid(username: String) -> Bool {
        username.range(of: "^[a-z0-9_]{3,20}$", options: .regularExpression) != nil
    }

    func register(username raw: String, password: String) throws -> UserAccount {
        let name = Self.normalized(raw)
        guard Self.isValid(username: name) else { throw AuthError.invalidUsername }
        guard password.count >= 8 else { throw AuthError.weakPassword }
        guard try findUser(named: name) == nil else { throw AuthError.usernameTaken }

        let salt = PasswordHasher.randomSalt()
        let user = UserAccount(
            username: name,
            passwordHash: PasswordHasher.hash(password, salt: salt),
            salt: salt)
        context.insert(user)
        do { try context.save() } catch {
            context.rollback()
            throw AuthError.storage
        }
        return user
    }

    func login(username raw: String, password: String) throws -> UserAccount {
        let name = Self.normalized(raw)
        guard let user = try findUser(named: name), !user.isDemo,
            let hash = user.passwordHash, let salt = user.salt,
            PasswordHasher.constantTimeEqual(hash, PasswordHasher.hash(password, salt: salt))
        else { throw AuthError.invalidCredentials }
        return user
    }

    func user(id: UUID) -> UserAccount? {
        let descriptor = FetchDescriptor<UserAccount>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    func updateBio(_ bio: String, for user: UserAccount) throws {
        user.bio = String(bio.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
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

/// Текущая сессия: кто вошёл, и запоминание входа между запусками. Сами аккаунты хранит `AuthProvider`.
@MainActor @Observable
final class AppSession {
    private(set) var currentUser: UserAccount?
    @ObservationIgnored private let auth: any AuthProvider
    @ObservationIgnored private let defaults: UserDefaults
    private static let sessionKey = "session.userID"

    init(auth: any AuthProvider, defaults: UserDefaults = .standard) {
        self.auth = auth
        self.defaults = defaults
        restore()
    }

    convenience init(context: ModelContext, defaults: UserDefaults = .standard) {
        self.init(auth: LocalAuthProvider(context: context), defaults: defaults)
    }

    func register(username: String, password: String) throws {
        start(try auth.register(username: username, password: password))
    }

    func login(username: String, password: String) throws {
        start(try auth.login(username: username, password: password))
    }

    func logout() {
        defaults.removeObject(forKey: Self.sessionKey)
        currentUser = nil
    }

    func updateBio(_ bio: String) throws {
        guard let user = currentUser else { return }
        try auth.updateBio(bio, for: user)
    }

    private func start(_ user: UserAccount) {
        defaults.set(user.id.uuidString, forKey: Self.sessionKey)
        currentUser = user
    }

    private func restore() {
        guard let raw = defaults.string(forKey: Self.sessionKey), let id = UUID(uuidString: raw) else { return }
        currentUser = auth.user(id: id)
    }
}
