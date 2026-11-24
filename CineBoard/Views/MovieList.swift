import SwiftUI

// MARK: - Модель списка фильмов (лента и поиск)

@MainActor @Observable
final class MovieListModel {
    enum Phase: Equatable { case loading, loaded, empty, failed(String) }

    private(set) var movies: [Movie] = []
    private(set) var phase: Phase = .loading
    private(set) var isLoadingMore = false
    private(set) var loadMoreFailed = false
    private var page = 0
    private var totalPages = 1
    private let fetch: @Sendable (Int) async throws -> MoviePage

    init(fetch: @escaping @Sendable (Int) async throws -> MoviePage) { self.fetch = fetch }

    func loadFirst() async {
        phase = .loading
        do {
            let result = try await fetch(1)
            page = 1
            totalPages = result.totalPages
            movies = unique(result.results)
            phase = movies.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(userMessage(for: error))
        }
    }

    /// Pull-to-refresh: при ошибке сохраняет уже загруженное.
    func refresh() async {
        guard let result = try? await fetch(1) else { return }
        page = 1
        totalPages = result.totalPages
        movies = unique(result.results)
        phase = movies.isEmpty ? .empty : .loaded
    }

    func loadMoreIfNeeded(current movie: Movie) async {
        guard phase == .loaded, !isLoadingMore, page < totalPages,
            movies.suffix(6).contains(where: { $0.id == movie.id })
        else { return }
        isLoadingMore = true
        loadMoreFailed = false
        defer { isLoadingMore = false }
        do {
            let result = try await fetch(page + 1)
            page += 1
            totalPages = result.totalPages
            movies += unique(result.results, existing: movies)
        } catch is CancellationError {
        } catch {
            loadMoreFailed = true
        }
    }

    private func unique(_ new: [Movie], existing: [Movie] = []) -> [Movie] {
        var seen = Set(existing.map(\.id))
        return new.filter { seen.insert($0.id).inserted }
    }
}

// MARK: - «Pinterest»-сетка

struct CardAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    var isDestructive = false
    let handler: () -> Void
}

struct MovieMasonry: View {
    let movies: [Movie]
    var onSave: ((Movie) -> Void)?
    var onAppearCard: ((Movie) -> Void)?
    var actions: (Movie) -> [CardAction] = { _ in [] }

    /// Детерминированные разные пропорции карточек создают «рваный» ритм сетки.
    static func ratio(for movie: Movie) -> CGFloat { [1.5, 1.35, 1.65][abs(movie.id) % 3] }

    private var columns: [[Movie]] {
        var cols: [[Movie]] = [[], []]
        var heights: [CGFloat] = [0, 0]
        for m in movies {
            let i = heights[0] <= heights[1] ? 0 : 1
            cols[i].append(m)
            heights[i] += Self.ratio(for: m) + 0.3
        }
        return cols
    }

    var body: some View {
        let cols = columns
        HStack(alignment: .top, spacing: 12) {
            ForEach(0..<2, id: \.self) { i in
                LazyVStack(spacing: 14) {
                    ForEach(cols[i]) { card($0) }
                }
            }
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func card(_ movie: Movie) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                NavigationLink(value: movie) {
                    PosterImage(path: movie.posterPath, title: movie.title, size: .w342, ratio: Self.ratio(for: movie))
                }
                .buttonStyle(.plain)

                if let onSave {
                    Button {
                        onSave(movie)
                    } label: {
                        Image(systemName: "bookmark.fill")
                            .font(.subheadline)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(8)
                    .accessibilityLabel("Сохранить «\(movie.title)» в подборку")
                }
            }
            NavigationLink(value: movie) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(movie.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    if let meta = meta(movie) { Text(meta).font(.caption).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .onAppear { onAppearCard?(movie) }
        .contextMenu {
            ForEach(actions(movie)) { a in
                Button(role: a.isDestructive ? .destructive : nil) {
                    a.handler()
                } label: {
                    Label(a.title, systemImage: a.systemImage)
                }
            }
        }
    }

    private func meta(_ m: Movie) -> String? {
        var parts: [String] = []
        if let y = m.year { parts.append(y) }
        if let r = m.voteAverage, r > 0 { parts.append("★ " + String(format: "%.1f", r)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Контент списка со всеми состояниями

struct MovieListContent: View {
    let model: MovieListModel
    var emptyTitle: String
    var emptyMessage: String
    @State private var movieToSave: Movie?

    var body: some View {
        ScrollView {
            switch model.phase {
            case .loading:
                SkeletonGrid().padding(.top, 8)
            case .failed(let message):
                ErrorStateView(message: message) { Task { await model.loadFirst() } }.padding(.top, 60)
            case .empty:
                ContentUnavailableView(emptyTitle, systemImage: "film.stack", description: Text(emptyMessage)).padding(
                    .top, 60)
            case .loaded:
                MovieMasonry(
                    movies: model.movies,
                    onSave: { movieToSave = $0 },
                    onAppearCard: { m in Task { await model.loadMoreIfNeeded(current: m) } })
                footer
            }
        }
        .refreshable { await model.refresh() }
        .sheet(item: $movieToSave) { SaveToCollectionSheet(movie: $0) }
    }

    @ViewBuilder
    private var footer: some View {
        if model.isLoadingMore {
            ProgressView().padding()
        } else if model.loadMoreFailed {
            Button("Не удалось загрузить ещё. Повторить") {
                if let last = model.movies.last { Task { await model.loadMoreIfNeeded(current: last) } }
            }
            .padding()
        }
        TMDBAttribution()
    }
}

// MARK: - Лента

struct FeedView: View {
    @Environment(\.catalog) private var catalog
    @State private var model: MovieListModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    MovieListContent(
                        model: model, emptyTitle: "Лента пуста",
                        emptyMessage: "Каталог не вернул фильмов. Потяните вниз, чтобы обновить.")
                } else {
                    Color.clear
                }
            }
            .navigationTitle("Лента")
            .appDestinations()
            .task {
                if model == nil {
                    model = MovieListModel { [catalog] page in try await catalog.trending(page: page) }
                }
                if model?.phase == .loading { await model?.loadFirst() }
            }
        }
    }
}

// MARK: - Поиск

struct SearchView: View {
    @Environment(\.catalog) private var catalog
    @State private var query = ""
    @State private var model: MovieListModel?
    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Group {
                if let model, !trimmed.isEmpty {
                    MovieListContent(
                        model: model, emptyTitle: "Ничего не найдено",
                        emptyMessage: "Попробуйте изменить запрос или проверить написание.")
                } else {
                    ContentUnavailableView(
                        "Поиск фильмов", systemImage: "magnifyingglass",
                        description: Text("Введите название фильма, чтобы найти его в каталоге TMDB."))
                }
            }
            .navigationTitle("Поиск")
            .searchable(text: $query, prompt: "Название фильма")
            .appDestinations()
            .task(id: trimmed) {
                let q = trimmed
                guard !q.isEmpty else { model = nil; return }
                try? await Task.sleep(for: .milliseconds(400))  // debounce
                guard !Task.isCancelled else { return }
                let m = MovieListModel { [catalog] page in try await catalog.search(query: q, page: page) }
                model = m
                await m.loadFirst()
            }
        }
    }
}
