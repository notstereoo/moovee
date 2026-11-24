import Foundation
import SwiftData

enum ReviewError: LocalizedError, Equatable {
    case invalidRating, textTooLong, notAuthor, saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidRating: "Поставьте оценку от 1 до 10."
        case .textTooLong: "Отзыв слишком длинный: не более \(ReviewRules.maxTextLength) символов."
        case .notAuthor: "Редактировать можно только свои отзывы."
        case .saveFailed: "Не удалось сохранить отзыв. Повторите попытку."
        }
    }
}

@MainActor @Observable
final class LocalReviewRepository: ReviewRepository {
    private(set) var revision = 0
    @ObservationIgnored private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    // MARK: Чтение

    func reviews(forMovie id: Int) -> [Review] {
        fetch(FetchDescriptor<Review>(predicate: #Predicate { $0.movieID == id }))
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func reviews(by user: UserAccount) -> [Review] {
        user.reviews.sorted { $0.updatedAt > $1.updatedAt }
    }

    func review(by user: UserAccount, movieID: Int) -> Review? {
        user.reviews.first { $0.movieID == movieID }
    }

    func communityRating(forMovie id: Int) -> CommunityRating? {
        let list = reviews(forMovie: id)
        guard !list.isEmpty else { return nil }
        let sum = list.reduce(0) { $0 + $1.rating }
        return CommunityRating(average: Double(sum) / Double(list.count), count: list.count)
    }

    private func fetch(_ descriptor: FetchDescriptor<Review>) -> [Review] {
        (try? context.fetch(descriptor)) ?? []
    }

    // MARK: Изменение

    func save(movie: Movie, rating: Int, text: String, as user: UserAccount) throws -> Review {
        guard ReviewRules.ratingRange.contains(rating) else { throw ReviewError.invalidRating }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.count <= ReviewRules.maxTextLength else { throw ReviewError.textTooLong }

        let review: Review
        if let existing = self.review(by: user, movieID: movie.id) {
            existing.rating = rating
            existing.text = body
            existing.updatedAt = .now
            review = existing
        } else {
            review = Review(movie: movie, rating: rating, text: body)
            context.insert(review)
            review.author = user
        }
        try commit()
        return review
    }

    func delete(_ review: Review, as user: UserAccount) throws {
        guard review.author?.id == user.id else { throw ReviewError.notAuthor }
        context.delete(review)
        try commit()
    }

    private func commit() throws {
        do {
            try context.save()
            revision += 1
        } catch {
            context.rollback()
            throw ReviewError.saveFailed
        }
    }
}
