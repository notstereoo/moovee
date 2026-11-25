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
            #if DEBUG
                if PreviewSupport.isActive {
                    let (container, deps) = try PreviewSupport.makeDependencies()
                    self.container = container
                    _dependencies = State(initialValue: deps)
                    return
                }
                if UITestSupport.isActive {
                    let (container, deps) = try UITestSupport.makeDependencies()
                    self.container = container
                    _dependencies = State(initialValue: deps)
                    return
                }
            #endif
            let container = try AppSchema.makeContainer()
            DemoSeeder.seedIfNeeded(container.mainContext)
            self.container = container
            _dependencies = State(initialValue: .local(context: container.mainContext, legacyDefaults: .standard))
        } catch {
            fatalError("Could not open local storage: \(error)")
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        #if DEBUG
            if let kind = CropPreviewSupport.kind {
                ImageCropView(
                    request: CropRequest(kind: kind, image: CropPreviewSupport.sampleImage()), onCancel: {}, onDone: { _ in })
            } else {
                RootView()
            }
        #else
            RootView()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            rootContent
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
