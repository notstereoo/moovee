import Foundation
import SwiftData

enum CollectionError: LocalizedError, Equatable {
    case notOwner, emptyTitle, saveFailed

    var errorDescription: String? {
        switch self {
        case .notOwner: String(localized: "Редактировать можно только свои подборки.")
        case .emptyTitle: String(localized: "Введите название подборки.")
        case .saveFailed: String(localized: "Не удалось сохранить изменения. Повторите попытку.")
        }
    }
}

/// Локальная реализация на SwiftData — единственная точка изменения коллекций.
@MainActor @Observable
final class LocalCollectionRepository: CollectionRepository {
    private(set) var revision = 0
    @ObservationIgnored private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    // MARK: Чтение

    func collections(ownedBy user: UserAccount) -> [MovieCollection] {
        allCollections().filter { $0.owner?.id == user.id }
    }

    func publicCollections(excluding user: UserAccount?) -> [MovieCollection] {
        allCollections().filter { $0.isPublic && $0.owner != nil && $0.owner?.id != user?.id }
    }

    private func allCollections() -> [MovieCollection] {
        let descriptor = FetchDescriptor<MovieCollection>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: Изменение

    func create(title: String, details: String, isPublic: Bool, as user: UserAccount) throws -> MovieCollection {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw CollectionError.emptyTitle }
        let c = MovieCollection(
            title: t, details: details.trimmingCharacters(in: .whitespacesAndNewlines), isPublic: isPublic)
        context.insert(c)
        c.owner = user
        try commit()
        return c
    }

    func update(_ c: MovieCollection, title: String, details: String, isPublic: Bool, as user: UserAccount) throws {
        try authorize(c, user)
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw CollectionError.emptyTitle }
        c.title = t
        c.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        c.isPublic = isPublic
        try commit()
    }

    func delete(_ c: MovieCollection, as user: UserAccount) throws {
        try authorize(c, user)
        context.delete(c)
        try commit()
    }

    func add(_ movie: Movie, to c: MovieCollection, as user: UserAccount) throws {
        try authorize(c, user)
        guard !c.items.contains(where: { $0.movieID == movie.id }) else { return }
        let item = CollectionItem(movie: movie)
        item.position = (c.items.map(\.position).max() ?? -1) + 1
        context.insert(item)
        item.collection = c
        try commit()
    }

    func remove(movieID: Int, from c: MovieCollection, as user: UserAccount) throws {
        try authorize(c, user)
        for item in c.items where item.movieID == movieID {
            if c.coverPosterPath != nil, c.coverPosterPath == item.posterPath { c.coverPosterPath = nil }
            context.delete(item)
        }
        try commit()
    }

    func setCover(of c: MovieCollection, movieID: Int, as user: UserAccount) throws {
        try authorize(c, user)
        guard let path = c.items.first(where: { $0.movieID == movieID })?.posterPath else { return }
        c.coverPosterPath = path
        try commit()
    }

    func moveItems(in c: MovieCollection, from source: IndexSet, to destination: Int, as user: UserAccount) throws {
        try authorize(c, user)
        let list = reordered(c.items(sortedBy: .manual), from: source, to: destination)
        for (index, item) in list.enumerated() { item.position = index }
        try commit()
    }

    private func authorize(_ c: MovieCollection, _ user: UserAccount) throws {
        guard c.owner?.id == user.id else { throw CollectionError.notOwner }
    }

    private func commit() throws {
        do {
            try context.save()
            revision += 1
        } catch {
            context.rollback()
            throw CollectionError.saveFailed
        }
    }
}
