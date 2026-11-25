import CryptoKit
import Foundation

/// Хранилище байтов по строковому ключу (диск в приложении, память в тестах).
protocol CatalogCacheStore: Sendable {
    func data(for key: String) -> Data?
    func store(_ data: Data, for key: String)
}

final class DiskCatalogCache: CatalogCacheStore, @unchecked Sendable {
    private let directory: URL
    private let fileManager = FileManager.default

    /// Каталог кэша в `Caches` (система может очистить его сама — для кэша это нормально).
    static let standard = DiskCatalogCache(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("catalog-cache", isDirectory: true))

    init(directory: URL, maxAge: TimeInterval = 14 * 24 * 3600) {
        self.directory = directory
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        prune(olderThan: maxAge)
    }

    func data(for key: String) -> Data? { try? Data(contentsOf: url(for: key)) }

    func store(_ data: Data, for key: String) { try? data.write(to: url(for: key), options: .atomic) }

    private func url(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest).appendingPathExtension("json")
    }

    private func prune(olderThan maxAge: TimeInterval) {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        for file in files {
            let date = (try? file.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            if Date().timeIntervalSince(date) > maxAge { try? fileManager.removeItem(at: file) }
        }
    }
}

final class MemoryCatalogCache: CatalogCacheStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    func data(for key: String) -> Data? { lock.withLock { storage[key] } }
    func store(_ data: Data, for key: String) { lock.withLock { storage[key] = data } }
}

/// Декоратор каталога: успешные ответы сохраняет, а при временных сбоях сети отдаёт последнее сохранённое.
struct CachingCatalog: MovieCatalog {
    let base: any MovieCatalog
    let cache: any CatalogCacheStore

    static func standard(base: any MovieCatalog = TMDBClient()) -> CachingCatalog {
        CachingCatalog(base: base, cache: DiskCatalogCache.standard)
    }

    var isConfigured: Bool { base.isConfigured }

    func trending(page: Int) async throws -> MoviePage {
        try await cached("v2-en-trending-\(page)", { try await base.trending(page: page) }, markCached: Self.markCached)
    }

    func search(query: String, page: Int) async throws -> MoviePage {
        let key = "v2-en-search-\(query.lowercased())-\(page)"
        return try await cached(key, { try await base.search(query: query, page: page) }, markCached: Self.markCached)
    }

    func details(id: Int) async throws -> Movie {
        try await cached("v2-en-details-\(id)", { try await base.details(id: id) }, markCached: { $0 })
    }

    private static func markCached(_ page: MoviePage) -> MoviePage {
        var copy = page
        copy.isFromCache = true
        return copy
    }

    private func cached<T: Codable>(
        _ key: String, _ fetch: () async throws -> T, markCached: (T) -> T
    ) async throws -> T {
        do {
            let value = try await fetch()
            if let data = try? JSONEncoder().encode(value) { cache.store(data, for: key) }
            return value
        } catch let error as TMDBError where error.allowsCachedFallback {
            if let data = cache.data(for: key), let value = try? TMDBClient.decoder.decode(T.self, from: data) {
                return markCached(value)
            }
            throw error
        }
    }
}
