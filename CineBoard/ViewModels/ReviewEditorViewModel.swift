import Foundation

@MainActor @Observable
final class ReviewEditorViewModel {
    let movie: Movie
    /// 0 — оценка ещё не выбрана.
    var rating: Int
    var text: String
    var errorMessage: String?
    private let existing: Review?
    private let repository: any ReviewRepository
    private let session: AppSession

    init(movie: Movie, reviews: any ReviewRepository, session: AppSession) {
        self.movie = movie
        self.repository = reviews
        self.session = session
        let current = session.currentUser.flatMap { reviews.review(by: $0, movieID: movie.id) }
        existing = current
        rating = current?.rating ?? 0
        text = current?.text ?? ""
    }

    var isEditing: Bool { existing != nil }
    var remaining: Int { ReviewRules.maxTextLength - text.count }
    var canSave: Bool { ReviewRules.ratingRange.contains(rating) && remaining >= 0 }

    func save() -> Bool {
        guard let me = session.currentUser else { return false }
        do {
            _ = try repository.save(movie: movie, rating: rating, text: text, as: me)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func delete() -> Bool {
        guard let me = session.currentUser, let existing else { return false }
        do {
            try repository.delete(existing, as: me)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }
}
