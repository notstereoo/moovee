import Foundation
import Security

enum SecretStoreError: Error, Equatable {
    case failed(OSStatus)
}

/// Хранилище секретов (хэши паролей, идентификатор сессии, счётчики попыток).
protocol SecretStore: Sendable {
    func data(for key: String) -> Data?
    func set(_ data: Data, for key: String) throws
    func remove(_ key: String)
}

/// Хранение в Keychain. Доступ после первой разблокировки устройства; в SwiftData и `UserDefaults` секретов нет.
struct KeychainSecretStore: SecretStore {
    let service: String

    static let standard = KeychainSecretStore(service: Bundle.main.bundleIdentifier ?? "CineBoard")

    private func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    func data(for key: String) -> Data? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func set(_ data: Data, for key: String) throws {
        let status = SecItemUpdate(query(key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw SecretStoreError.failed(status) }

        var add = query(key)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw SecretStoreError.failed(addStatus) }
    }

    func remove(_ key: String) { SecItemDelete(query(key) as CFDictionary) }
}

/// В памяти: для тестов и режима `-uitest`.
final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]
    /// Для тестов отказа хранилища.
    var failsOnWrite = false

    func data(for key: String) -> Data? { lock.withLock { storage[key] } }

    func set(_ data: Data, for key: String) throws {
        if failsOnWrite { throw SecretStoreError.failed(-1) }
        lock.withLock { storage[key] = data }
    }

    func remove(_ key: String) { lock.withLock { _ = storage.removeValue(forKey: key) } }

    var keys: [String] { lock.withLock { Array(storage.keys) } }
}
