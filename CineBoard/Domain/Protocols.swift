import Foundation

/// Источник аккаунтов. Сейчас — локальный (SwiftData), позже — серверный (Sign in with Apple и т. п.).
@MainActor
protocol AuthProvider {
    func register(username: String, password: String) throws -> UserAccount
    func login(username: String, password: String) throws -> UserAccount
    func user(id: UUID) -> UserAccount?
    func updateBio(_ bio: String, for user: UserAccount) throws
}

/// Хранилище подборок. Каждая изменяющая операция проверяет, что `user` — владелец.
/// `revision` растёт после каждого успешного изменения — по нему ViewModel'и обновляют списки.
@MainActor
protocol CollectionRepository: AnyObject {
    var revision: Int { get }

    func collections(ownedBy user: UserAccount) -> [MovieCollection]
    /// Публичные подборки всех, кроме `user`.
    func publicCollections(excluding user: UserAccount?) -> [MovieCollection]

    func create(title: String, details: String, isPublic: Bool, as user: UserAccount) throws -> MovieCollection
    func update(_ c: MovieCollection, title: String, details: String, isPublic: Bool, as user: UserAccount) throws
    func delete(_ c: MovieCollection, as user: UserAccount) throws
    func add(_ movie: Movie, to c: MovieCollection, as user: UserAccount) throws
    func remove(movieID: Int, from c: MovieCollection, as user: UserAccount) throws
    func setCover(of c: MovieCollection, movieID: Int, as user: UserAccount) throws
}
