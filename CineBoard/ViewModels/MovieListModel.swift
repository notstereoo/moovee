import Foundation

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
