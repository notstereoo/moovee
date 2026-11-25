#if DEBUG
    import Foundation
    import SwiftData
    import UIKit

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
            (603, "The Matrix", "1999"), (278, "The Shawshank Redemption", "1994"), (238, "The Godfather", "1972"),
        ].map {
            Movie(
                id: $0.0, title: $0.1, overview: "Description of \"\($0.1)\".", posterPath: nil, backdropPath: nil,
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

    /// Режим `-preview`: чистое хранилище, настоящий каталог и готовый вошедший пользователь с фото, подписками и лайками.
    /// Нужен только для просмотра интерфейса на симуляторе.
    enum PreviewSupport {
        static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-preview") }

        @MainActor
        static func makeDependencies() throws -> (ModelContainer, AppDependencies) {
            let container = try AppSchema.makeContainer(inMemory: true)
            let context = container.mainContext
            DemoSeeder.seedIfNeeded(context)
            let deps = AppDependencies.local(context: context, secrets: InMemorySecretStore())
            try deps.session.register(username: "timofey", password: "password123")
            let me = try XCTUnwrapLike(deps.session.currentUser)

            let banner = gradientImage(size: CGSize(width: 1500, height: 500), colors: [.systemIndigo, .systemPink])
            let avatar = gradientImage(size: CGSize(width: 512, height: 512), colors: [.systemOrange, .systemRed])
            try deps.session.updateProfile(
                ProfileEdit(
                    displayName: "Timofey", bio: "Movie nights, slow cinema and neon. Always up for a recommendation.",
                    isPrivate: false,
                    avatar: ImageProcessing.avatarJPEG(from: avatar).map(ImageChange.set) ?? .keep,
                    banner: ImageProcessing.bannerJPEG(from: banner).map(ImageChange.set) ?? .keep))

            func movie(_ id: Int, _ title: String, _ year: String) -> Movie {
                Movie(
                    id: id, title: title, overview: nil, posterPath: nil, backdropPath: nil, releaseDate: year,
                    voteAverage: nil, runtime: nil, genres: nil)
            }
            let neon = try deps.collections.create(
                title: "Late night neon", details: "Rain, synths and glowing signs.", isPublic: true, as: me)
            for m in [movie(335984, "Blade Runner 2049", "2017"), movie(64690, "Drive", "2011"), movie(152601, "Her", "2013")] {
                try deps.collections.add(m, to: neon, as: me)
            }
            let cozy = try deps.collections.create(
                title: "Cozy evening", details: "Warm and beautiful.", isPublic: true, as: me)
            for m in [movie(129, "Spirited Away", "2001"), movie(120467, "The Grand Budapest Hotel", "2014")] {
                try deps.collections.add(m, to: cozy, as: me)
            }
            for m in [movie(496243, "Parasite", "2019"), movie(244786, "Whiplash", "2014"), movie(129, "Spirited Away", "2001")] {
                try deps.favorites.add(m, as: me)
            }
            _ = try deps.reviews.save(
                movie: movie(496243, "Parasite", "2019"), rating: 9, text: "Go in knowing nothing. Worth every hype.",
                as: me)

            let users = try context.fetch(FetchDescriptor<UserAccount>())
            if let anna = users.first(where: { $0.username == "anna_films" }),
                let max = users.first(where: { $0.username == "max_cinema" })
            {
                try deps.social.follow(max, as: me)
                try deps.social.follow(anna, as: me)
                try deps.social.follow(me, as: max)  // Max и я — друзья
                try deps.social.follow(me, as: anna)
                try deps.social.follow(me, as: users.first(where: { $0.isDemo })!)
                try deps.social.setLiked(true, neon, as: anna)
                try deps.social.setLiked(true, neon, as: max)
                try deps.social.setLiked(true, cozy, as: max)
                for c in max.collections.prefix(1) + anna.collections.filter({ $0.isPublic }).prefix(1) {
                    try deps.social.setSaved(true, c, as: me)
                }
            }
            return (container, deps)
        }

        private static func XCTUnwrapLike<T>(_ value: T?) throws -> T {
            guard let value else { throw AuthError.storage }
            return value
        }

        private static func gradientImage(size: CGSize, colors: [UIColor]) -> Data {
            UIGraphicsImageRenderer(size: size).pngData { ctx in
                let cg = ctx.cgContext
                let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: [0, 1])!
                cg.drawLinearGradient(
                    gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
                UIColor.white.withAlphaComponent(0.18).setFill()
                cg.fillEllipse(in: CGRect(x: size.width * 0.55, y: -size.height * 0.3, width: size.height * 1.2, height: size.height * 1.2))
            }
        }
    }
#endif
