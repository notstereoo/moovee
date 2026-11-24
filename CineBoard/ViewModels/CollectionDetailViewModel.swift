import Foundation

@MainActor @Observable
final class CollectionDetailViewModel {
    enum Availability: Equatable { case available, removed, privateToViewer }

    let collection: MovieCollection
    var errorMessage: String?
    private let repository: any CollectionRepository
    private let session: AppSession

    init(collection: MovieCollection, repository: any CollectionRepository, session: AppSession) {
        self.collection = collection
        self.repository = repository
        self.session = session
    }

    /// Защита от обращения к удалённой модели и от доступа к чужой приватной подборке.
    var availability: Availability {
        if collection.modelContext == nil || collection.isDeleted { return .removed }
        if !collection.isVisible(to: session.currentUser) { return .privateToViewer }
        return .available
    }

    var isOwner: Bool {
        guard let me = session.currentUser else { return false }
        return collection.owner?.id == me.id
    }

    var movies: [Movie] { collection.sortedItems.map(Movie.init(item:)) }

    func setCover(movieID: Int) {
        perform { try repository.setCover(of: collection, movieID: movieID, as: $0) }
    }

    func remove(movieID: Int) {
        perform { try repository.remove(movieID: movieID, from: collection, as: $0) }
    }

    /// `true`, если подборка удалена.
    @discardableResult
    func delete() -> Bool {
        perform { try repository.delete(collection, as: $0) }
    }

    @discardableResult
    private func perform(_ op: (UserAccount) throws -> Void) -> Bool {
        guard let user = session.currentUser else { return false }
        do {
            try op(user)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }
}
