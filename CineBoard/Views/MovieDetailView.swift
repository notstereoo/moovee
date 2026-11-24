import SwiftUI

struct MovieDetailView: View {
    let movie: Movie

    var body: some View {
        ViewModelHost(make: { $0.makeMovieDetailViewModel(movie) }) { MovieDetailContent(model: $0) }
    }
}

private struct MovieDetailContent: View {
    @Bindable var model: MovieDetailViewModel
    @State private var showSave = false
    @State private var showReviewEditor = false

    private var shown: Movie { model.shown }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerBlock
                actions

                if model.isLoading && model.detail == nil { ProgressView("Загружаем подробности…").frame(maxWidth: .infinity) }
                loadErrorBlock
                overview
                myReviewSection
                reviewsSection
                TMDBAttribution()
            }
            .padding()
        }
        .navigationTitle(shown.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSave) { SaveToCollectionSheet(movie: shown) }
        .sheet(isPresented: $showReviewEditor) { ReviewEditorView(movie: shown) }
        .errorAlert($model.actionError)
        .task { await model.load() }
    }

    // MARK: Блоки

    private var headerBlock: some View {
        HStack(alignment: .top, spacing: 16) {
            PosterImage(path: shown.posterPath, title: shown.title, size: .w500).frame(width: 140)
            VStack(alignment: .leading, spacing: 8) {
                Text(shown.title).font(.title2.bold())
                if let y = shown.year { Text(y).foregroundStyle(.secondary) }
                CommunityRatingLabel(rating: model.communityRating)
                if let r = shown.voteAverage, r > 0 {
                    Label("TMDB \(String(format: "%.1f", r))", systemImage: "star.fill")
                        .font(.subheadline).foregroundStyle(.orange)
                }
                if let rt = shown.runtime, rt > 0 { Text("\(rt) мин").foregroundStyle(.secondary) }
                if let g = shown.genres, !g.isEmpty {
                    Text(g.map(\.name).joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                showSave = true
            } label: {
                Label("Сохранить в подборку", systemImage: "bookmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            HStack(spacing: 10) {
                Button {
                    model.toggleFavorite()
                } label: {
                    Label(
                        model.isFavorite ? "В любимых" : "В любимые",
                        systemImage: model.isFavorite ? "heart.fill" : "heart"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(model.isFavorite ? .pink : .accentColor)

                Button {
                    showReviewEditor = true
                } label: {
                    Label(model.myReview == nil ? "Оценить" : "Мой отзыв", systemImage: "star.bubble")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var loadErrorBlock: some View {
        if let message = model.loadError {
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle").font(.subheadline)
                Button("Повторить") { Task { await model.load() } }
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var overview: some View {
        if let overview = shown.overview, !overview.isEmpty {
            Text("Описание").font(.headline)
            Text(overview)
        } else if model.detail != nil {
            Text("Описание отсутствует.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var myReviewSection: some View {
        if let mine = model.myReview {
            Text("Ваш отзыв").font(.headline)
            ReviewRow(review: mine)
        }
    }

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Отзывы").font(.headline)
            let others = model.otherReviews
            if others.isEmpty {
                Text(model.myReview == nil ? "Отзывов пока нет. Будьте первым!" : "Других отзывов пока нет.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(others) { ReviewRow(review: $0) }
            }
        }
    }
}
