import Foundation
import SwiftData

/// Файлы базы доступны только при разблокированном устройстве (`NSFileProtectionComplete`).
/// Для новых файлов то же задаёт entitlement `default-data-protection`; здесь — для уже существующих.
enum StoreProtection {
    static func apply(to container: ModelContainer) {
        let fileManager = FileManager.default
        for configuration in container.configurations where !configuration.isStoredInMemoryOnly {
            let url = configuration.url
            for suffix in ["", "-wal", "-shm"] {
                let path = url.path + suffix
                guard fileManager.fileExists(atPath: path) else { continue }
                try? fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path)
            }
        }
    }
}
