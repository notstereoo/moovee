import SwiftData
import SwiftUI

/// Корень зависимостей приложения. ViewModel'и создаются только здесь, а во View попадают через `ViewModelHost`.
/// В тестах и превью можно подменить любую зависимость.
@MainActor @Observable
final class AppDependencies {
    let session: AppSession
    let collections: any CollectionRepository
    let reviews: any ReviewRepository
    let favorites: any FavoritesRepository
    let catalog: any MovieCatalog

    init(
        session: AppSession, collections: any CollectionRepository, reviews: any ReviewRepository,
        favorites: any FavoritesRepository, catalog: any MovieCatalog
    ) {
        self.session = session
        self.collections = collections
        self.reviews = reviews
        self.favorites = favorites
        self.catalog = catalog
    }

    /// Локальная конфигурация поверх SwiftData.
    static func local(
        context: ModelContext, catalog: any MovieCatalog = CachingCatalog.standard(), defaults: UserDefaults = .standard
    ) -> AppDependencies {
        AppDependencies(
            session: AppSession(context: context, defaults: defaults),
            collections: LocalCollectionRepository(context: context),
            reviews: LocalReviewRepository(context: context),
            favorites: LocalFavoritesRepository(context: context),
            catalog: catalog)
    }

    // MARK: Фабрики ViewModel'ей

    func makeFeedModel() -> MovieListModel {
        MovieListModel { [catalog] page in try await catalog.trending(page: page) }
    }

    func makeSearchModel(query: String) -> MovieListModel {
        MovieListModel { [catalog] page in try await catalog.search(query: query, page: page) }
    }

    func makeCollectionsViewModel() -> CollectionsViewModel {
        CollectionsViewModel(repository: collections, session: session)
    }

    func makeCollectionDetailViewModel(_ collection: MovieCollection) -> CollectionDetailViewModel {
        CollectionDetailViewModel(collection: collection, repository: collections, session: session)
    }

    func makeSaveViewModel(movie: Movie) -> SaveToCollectionViewModel {
        SaveToCollectionViewModel(movie: movie, repository: collections, session: session)
    }

    func makeMovieDetailViewModel(_ movie: Movie) -> MovieDetailViewModel {
        MovieDetailViewModel(
            movie: movie, catalog: catalog, reviews: reviews, favorites: favorites, session: session)
    }

    func makeReviewEditorViewModel(movie: Movie) -> ReviewEditorViewModel {
        ReviewEditorViewModel(movie: movie, reviews: reviews, session: session)
    }

    func makeProfileViewModel(user: UserAccount) -> ProfileViewModel {
        ProfileViewModel(user: user, collections: collections, reviews: reviews, favorites: favorites, session: session)
    }

    func makeEditorViewModel(collection: MovieCollection?) -> CollectionEditorViewModel {
        CollectionEditorViewModel(collection: collection, repository: collections, session: session)
    }
}

/// Создаёт ViewModel один раз при появлении экрана, беря зависимости из Environment.
struct ViewModelHost<Model: AnyObject, Content: View>: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: Model?
    let make: (AppDependencies) -> Model
    @ViewBuilder let content: (Model) -> Content

    var body: some View {
        if let model {
            content(model)
        } else {
            Color.clear.onAppear { model = make(dependencies) }
        }
    }
}
