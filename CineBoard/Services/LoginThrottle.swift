import Foundation

/// Замедляет подбор пароля: после нескольких неудач вход временно блокируется, задержка растёт вдвое.
/// Счётчики лежат в `SecretStore`, поэтому перезапуск приложения их не сбрасывает.
struct LoginThrottle {
    struct Record: Codable, Equatable {
        var failures: Int
        var lastFailure: Date
    }

    static let freeAttempts = 5
    static let baseDelay: TimeInterval = 30
    static let maxDelay: TimeInterval = 15 * 60
    private static let recordLifetime: TimeInterval = 24 * 3600
    private static let storageKey = "login.throttle"

    let secrets: any SecretStore
    var now: @Sendable () -> Date = { Date() }

    static func delay(afterFailures failures: Int) -> TimeInterval {
        guard failures >= freeAttempts else { return 0 }
        return min(baseDelay * pow(2, Double(failures - freeAttempts)), maxDelay)
    }

    /// Сколько секунд ещё нельзя пробовать войти (0 — можно).
    func lockRemaining(for username: String) -> TimeInterval {
        guard let record = load()[username] else { return 0 }
        let unlock = record.lastFailure.addingTimeInterval(Self.delay(afterFailures: record.failures))
        return max(0, unlock.timeIntervalSince(now()))
    }

    func recordFailure(for username: String) {
        var all = load()
        var record = all[username] ?? Record(failures: 0, lastFailure: now())
        record.failures += 1
        record.lastFailure = now()
        all[username] = record
        save(all)
    }

    func reset(for username: String) {
        var all = load()
        guard all.removeValue(forKey: username) != nil else { return }
        save(all)
    }

    private func load() -> [String: Record] {
        guard let data = secrets.data(for: Self.storageKey),
            let all = try? JSONDecoder().decode([String: Record].self, from: data)
        else { return [:] }
        let cutoff = now().addingTimeInterval(-Self.recordLifetime)
        return all.filter { $0.value.lastFailure > cutoff }
    }

    private func save(_ all: [String: Record]) {
        if all.isEmpty {
            secrets.remove(Self.storageKey)
        } else if let data = try? JSONEncoder().encode(all) {
            try? secrets.set(data, for: Self.storageKey)
        }
    }
}
