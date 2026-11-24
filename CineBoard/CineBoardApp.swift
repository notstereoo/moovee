import SwiftUI
import SwiftData

@main
struct CineBoardApp: App {
    private let container: ModelContainer
    @State private var session: AppSession
    private let catalog = TMDBClient()

    init() {
        do {
            let container = try ModelContainer(for: UserAccount.self, MovieCollection.self, CollectionItem.self)
            DemoSeeder.seedIfNeeded(container.mainContext)
            self.container = container
            _session = State(initialValue: AppSession(context: container.mainContext))
        } catch {
            fatalError("Не удалось открыть локальное хранилище: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(\.catalog, catalog)
                .task { await DemoSeeder.hydratePosters(context: container.mainContext, catalog: catalog) }
        }
        .modelContainer(container)
    }
}
#Preview {
    let container = try! ModelContainer(
        for: UserAccount.self, MovieCollection.self, CollectionItem.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    DemoSeeder.seedIfNeeded(container.mainContext)
    return RootView()
        .environment(AppSession(context: container.mainContext))
        .environment(\.catalog, TMDBClient())
        .modelContainer(container)
}
