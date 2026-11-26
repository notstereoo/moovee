import Foundation

@MainActor @Observable
final class CollectionEditorViewModel {
    let collection: MovieCollection?
    var title: String
    var details: String
    var isPublic: Bool
    /// Идентификатор цветовой темы карточки.
    var themeID: String
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
        themeID = collection.map { CollectionTheme.resolve(for: $0).id } ?? CollectionTheme.all[2].id
    }

    var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Возвращает сохранённую подборку или `nil` (причина — в `errorMessage`).
    func save() -> MovieCollection? {
        guard let user = session.currentUser else { return nil }
        do {
            if let collection {
                try repository.update(collection, title: title, details: details, isPublic: isPublic, as: user)
                try repository.setTheme(themeID, of: collection, as: user)
                return collection
            }
            let created = try repository.create(title: title, details: details, isPublic: isPublic, as: user)
            try repository.setTheme(themeID, of: created, as: user)
            return created
        } catch {
            errorMessage = userMessage(for: error)
            return nil
        }
    }
}
