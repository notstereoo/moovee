import Foundation

@MainActor @Observable
final class CollectionEditorViewModel {
    let collection: MovieCollection?
    var title: String
    var details: String
    var isPublic: Bool
    var errorMessage: String?
    private let repository: any CollectionRepository
    private let session: AppSession

    init(collection: MovieCollection?, repository: any CollectionRepository, session: AppSession) {
        self.collection = collection
        self.repository = repository
        self.session = session
        title = collection?.title ?? ""
        details = collection?.details ?? ""
        isPublic = collection?.isPublic ?? true
    }

    var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Возвращает сохранённую подборку или `nil` (причина — в `errorMessage`).
    func save() -> MovieCollection? {
        guard let user = session.currentUser else { return nil }
        do {
            if let collection {
                try repository.update(collection, title: title, details: details, isPublic: isPublic, as: user)
                return collection
            }
            return try repository.create(title: title, details: details, isPublic: isPublic, as: user)
        } catch {
            errorMessage = userMessage(for: error)
            return nil
        }
    }
}
