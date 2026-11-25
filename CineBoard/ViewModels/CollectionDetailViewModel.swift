import Foundation

@MainActor @Observable
final class CollectionDetailViewModel {
    enum Availability: Equatable { case available, removed, privateToViewer }

    let collection: MovieCollection
    var errorMessage: String?
    var query = ""
    var sort: CollectionSort = .added
    private let repository: any CollectionRepository
    private let social: any SocialRepository
    private let session: AppSession

    init(
        collection: MovieCollection, repository: any CollectionRepository, social: any SocialRepository,
        session: AppSession
    ) {
        self.collection = collection
        self.repository = repository
        self.social = social
        self.session = session
    }

    // MARK: Лайки и сохранение

    var likeCount: Int {
        _ = social.revision
        return social.likeCount(of: collection)
    }

    var isLiked: Bool {
        _ = social.revision
        guard let me = session.currentUser else { return false }
        return social.isLiked(collection, by: me)
    }

    var isSaved: Bool {
        _ = social.revision
        guard let me = session.currentUser else { return false }
        return social.isSaved(collection, by: me)
    }

    /// Лайкать и сохранять можно только чужие подборки.
    var canInteract: Bool { session.currentUser != nil && !isOwner }

    func toggleLike() {
        guard let me = session.currentUser else { return }
        do { try social.setLiked(!social.isLiked(collection, by: me), collection, as: me) } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func toggleSave() {
        guard let me = session.currentUser else { return }
        do { try social.setSaved(!social.isSaved(collection, by: me), collection, as: me) } catch {
            errorMessage = userMessage(for: error)
        }
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

    /// Фильмы с учётом поиска и выбранной сортировки.
    var movies: [Movie] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return collection.items(sortedBy: sort)
            .filter { q.isEmpty || $0.title.localizedCaseInsensitiveContains(q) }
            .map(Movie.init(item:))
    }

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Фильмы в порядке автора — для экрана перестановки.
    var manualOrder: [CollectionItem] { collection.items(sortedBy: .manual) }

    func moveItems(from source: IndexSet, to destination: Int) {
        perform { try repository.moveItems(in: collection, from: source, to: destination, as: $0) }
        sort = .manual
    }

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
