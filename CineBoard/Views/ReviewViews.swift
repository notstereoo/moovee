import SwiftUI

// MARK: - Выбор оценки 1–10

struct RatingPicker: View {
    @Binding var rating: Int

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(ReviewRules.ratingRange, id: \.self) { value in
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(value <= rating ? Color.orange : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .contentShape(Rectangle())
                        .onTapGesture { rating = value }
                }
            }
            Text(rating == 0 ? "Choose a rating" : "\(rating) of \(ReviewRules.ratingRange.upperBound)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(rating == 0 ? Color.secondary : .primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue(rating == 0 ? "not selected" : "\(rating) of 10")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(rating + 1, ReviewRules.ratingRange.upperBound)
            case .decrement: rating = max(rating - 1, ReviewRules.ratingRange.lowerBound)
            @unknown default: break
            }
        }
    }
}

// MARK: - Карточка отзыва

struct ReviewRow: View {
    let review: Review
    /// В профиле показываем фильм, под фильмом — автора.
    var showMovie = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !review.text.isEmpty { Text(review.text) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            if showMovie {
                NavigationLink(value: Movie(review: review)) {
                    HStack(spacing: 10) {
                        PosterImage(path: review.posterPath, title: review.movieTitle, size: .w185, ratio: 1.0)
                            .frame(width: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(review.movieTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text(dateText).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else if let author = review.author {
                NavigationLink(value: author) {
                    HStack(spacing: 8) {
                        AvatarView(user: author, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(author.shownName).font(.subheadline.weight(.semibold))
                            Text(dateText).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Label("\(review.rating)", systemImage: "star.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.orange)
                .accessibilityLabel("Rating \(review.rating) of 10")
        }
    }

    private var dateText: String { review.updatedAt.formatted(date: .abbreviated, time: .omitted) }
}

// MARK: - Рейтинг сообщества

struct CommunityRatingLabel: View {
    let rating: CommunityRating?

    var body: some View {
        if let rating {
            Label(
                "CineBoard \(String(format: "%.1f", rating.average)) · \(ratingsText(rating.count))",
                systemImage: "person.2.fill"
            )
            .font(.subheadline.weight(.medium))
        } else {
            Label("No CineBoard ratings yet", systemImage: "person.2")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

func ratingsText(_ n: Int) -> String { n == 1 ? "1 rating" : "\(n) ratings" }

// MARK: - Редактор отзыва

struct ReviewEditorView: View {
    let movie: Movie

    var body: some View {
        ViewModelHost(make: { $0.makeReviewEditorViewModel(movie: movie) }) { ReviewEditorContent(model: $0) }
    }
}

private struct ReviewEditorContent: View {
    @Bindable var model: ReviewEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Your rating") { RatingPicker(rating: $model.rating) }
                Section {
                    TextField("What do you think about the movie? (optional)", text: $model.text, axis: .vertical)
                        .lineLimit(4...10)
                } header: {
                    Text("Review")
                } footer: {
                    Text("Characters left: \(model.remaining)")
                        .foregroundStyle(model.remaining < 0 ? Color.red : .secondary)
                }
                if model.isEditing {
                    Section {
                        Button("Delete review", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(model.movie.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if model.save() { dismiss() } }.disabled(!model.canSave)
                }
            }
            .confirmationDialog("Delete review?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if model.delete() { dismiss() } }
                Button("Cancel", role: .cancel) {}
            }
            .errorAlert($model.errorMessage)
        }
    }
}
