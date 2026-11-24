#if DEBUG
    import Foundation
    import SwiftData

    /// Режим `-uitest`: чистое хранилище в памяти и детерминированный каталог без сети.
    /// Нужен только для UI-тестов, в Release-сборку не попадает.
    enum UITestSupport {
        static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-uitest") }

        @MainActor
        static func makeDependencies() throws -> (ModelContainer, AppDependencies) {
            let container = try AppSchema.makeContainer(inMemory: true)
            let deps = AppDependencies.local(
                context: container.mainContext, catalog: UITestCatalog(), secrets: InMemorySecretStore())
            return (container, deps)
        }
    }

    struct UITestCatalog: MovieCatalog {
        var isConfigured: Bool { true }

        private static let movies: [Movie] = [
            (603, "Матрица", "1999"), (278, "Побег из Шоушенка", "1994"), (238, "Крестный отец", "1972"),
        ].map {
            Movie(
                id: $0.0, title: $0.1, overview: "Описание фильма «\($0.1)».", posterPath: nil, backdropPath: nil,
                releaseDate: $0.2, voteAverage: 8.0, runtime: 120, genres: nil)
        }

        func trending(page: Int) async throws -> MoviePage {
            MoviePage(page: page, results: Self.movies, totalPages: 1)
        }

        func search(query: String, page: Int) async throws -> MoviePage {
            let found = Self.movies.filter { $0.title.localizedCaseInsensitiveContains(query) }
            return MoviePage(page: page, results: found, totalPages: 1)
        }

        func details(id: Int) async throws -> Movie {
            guard let movie = Self.movies.first(where: { $0.id == id }) else { throw TMDBError.badResponse }
            return movie
        }
    }
#endif
