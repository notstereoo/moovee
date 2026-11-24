import SwiftData
import SwiftUI

@main
struct CineBoardApp: App {
    private let container: ModelContainer
    @State private var dependencies: AppDependencies

    init() {
        // Постеры кэшируются на диске: ленты и профили открываются без повторной загрузки.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 300 << 20)
        do {
            let container = try AppSchema.makeContainer()
            DemoSeeder.seedIfNeeded(container.mainContext)
            self.container = container
            _dependencies = State(initialValue: .local(context: container.mainContext))
        } catch {
            fatalError("Не удалось открыть локальное хранилище: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
                .environment(dependencies.session)
                .environment(\.catalog, dependencies.catalog)
                .task { await SnapshotRefresher.refreshStale(context: container.mainContext, catalog: dependencies.catalog) }
        }
        .modelContainer(container)
    }
}

#Preview {
    let container = try! AppSchema.makeContainer(inMemory: true)
    DemoSeeder.seedIfNeeded(container.mainContext)
    let deps = AppDependencies.local(context: container.mainContext)
    return RootView()
        .environment(deps)
        .environment(deps.session)
        .environment(\.catalog, deps.catalog)
        .modelContainer(container)
}
