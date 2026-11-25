import SwiftUI

struct CollectionsView: View {
    var body: some View {
        ViewModelHost(make: { $0.makeCollectionsViewModel() }) { CollectionsContent(model: $0) }
    }
}

private struct CollectionsContent: View {
    @Bindable var model: CollectionsViewModel
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Section", selection: $model.scope) {
                        ForEach(CollectionsViewModel.Scope.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    let list = model.visible
                    if list.isEmpty {
                        emptyState.padding(.top, 40)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 16) {
                            ForEach(list) { c in
                                NavigationLink(value: c) {
                                    CollectionCard(collection: c, showOwner: model.scope == .discover)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }
            .navigationTitle("Collections")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New collection", systemImage: "plus") { showEditor = true }
                }
            }
            .sheet(isPresented: $showEditor) { CollectionEditorView() }
            .appDestinations()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.scope == .mine {
            ContentUnavailableView {
                Label("No collections yet", systemImage: "rectangle.stack.badge.plus")
            } description: {
                Text("Create your first collection and save movies to it from the feed and search.")
            } actions: {
                Button("Create collection") { showEditor = true }.buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView(
                "Nothing to show yet", systemImage: "globe",
                description: Text("Other users' public collections will appear here."))
        }
    }
}

struct CollectionCard: View {
    let collection: MovieCollection
    var showOwner = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterImage(path: collection.coverPath, title: collection.title, size: .w342, ratio: 1.2)
            Text(collection.title).font(.subheadline.weight(.semibold)).lineLimit(2)
            HStack(spacing: 4) {
                if !collection.isPublic { Image(systemName: "lock.fill") }
                Text(filmsText(collection.items.count))
                if showOwner, let owner = collection.owner { Text("· \(owner.shownName)").lineLimit(1) }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
