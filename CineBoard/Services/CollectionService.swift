import Foundation
import SwiftData

enum CollectionError: LocalizedError, Equatable {
    case notOwner, emptyTitle, saveFailed

    var errorDescription: String? {
        switch self {
        case .notOwner: "Редактировать можно только свои подборки."
        case .emptyTitle: "Введите название подборки."
        case .saveFailed: "Не удалось сохранить изменения. Повторите попытку."
        }
    }
}

/// Единственная точка изменения коллекций: каждая операция проверяет, что пользователь — владелец.
@MainActor
struct CollectionService {
    let context: ModelContext
    let user: UserAccount

    func create(title: String, details: String, isPublic: Bool) throws -> MovieCollection {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw CollectionError.emptyTitle }
        let c = MovieCollection(title: t, details: details.trimmingCharacters(in: .whitespacesAndNewlines), isPublic: isPublic)
        context.insert(c)
        c.owner = user
        try commit()
        return c
    }

    func update(_ c: MovieCollection, title: String, details: String, isPublic: Bool) throws {
        try authorize(c)
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw CollectionError.emptyTitle }
        c.title = t
        c.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        c.isPublic = isPublic
        try commit()
    }

    func delete(_ c: MovieCollection) throws {
        try authorize(c)
        context.delete(c)
        try commit()
    }

    func add(_ movie: Movie, to c: MovieCollection) throws {
        try authorize(c)
        guard !c.items.contains(where: { $0.movieID == movie.id }) else { return }
        let item = CollectionItem(movie: movie)
        context.insert(item)
        item.collection = c
        try commit()
    }

    func remove(movieID: Int, from c: MovieCollection) throws {
        try authorize(c)
        for item in c.items where item.movieID == movieID {
            if c.coverPosterPath != nil, c.coverPosterPath == item.posterPath { c.coverPosterPath = nil }
            context.delete(item)
        }
        try commit()
    }

    func setCover(of c: MovieCollection, movieID: Int) throws {
        try authorize(c)
        guard let path = c.items.first(where: { $0.movieID == movieID })?.posterPath else { return }
        c.coverPosterPath = path
        try commit()
    }

    private func authorize(_ c: MovieCollection) throws {
        guard c.owner?.id == user.id else { throw CollectionError.notOwner }
    }

    private func commit() throws {
        do { try context.save() } catch { context.rollback(); throw CollectionError.saveFailed }
    }
}
